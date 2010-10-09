#!/usr/bin/env ruby
require 'rubygems'
require 'gosu'

class Timer
  attr_accessor :time, :duration, :alarm

  def initialize(duration)
    @duration = duration
    reset
  end

  def update(delta)
    @time += delta
    @alarm = true if @time > @duration
  end

  def reset
    @time = 0
    @alarm = false
  end
end

class Tilemap
  attr_reader :width, :height

  def initialize(file, key)
    File.open(file, 'r') do|f|
      @width = f.gets.chomp.length
      f.rewind

      @height = f.readlines.length
      f.rewind

      @map = []
      while line = f.gets
        @map << line.chomp.split(//).map{|i| key[i]}
      end
      @map.flatten!
    end
  end

  def [](x, y)
    @map[ (y * @width) + x ]
  end

  def []=(x, y, val)
    @map[ (y * @width) + x ] = val
  end
end

class Snake
  attr_accessor :body, :direction, :move, :status, :timer

  DIRECTION = {
    Gosu::KbUp => [0, -1],
    Gosu::KbDown => [0, 1],
    Gosu::KbLeft => [-1, 0],
    Gosu::KbRight => [1, 0]
  }

  def initialize(map, length=3, duration=0.1)
    @map = map
    @direction = Gosu::KbUp
    @timer = Timer.new(duration)
    @status = :alive

    @body = []
    @body << [ @map.width / 2, @map.height / 2 ]
    @grow = length
  end

  def update(delta)
    @timer.update(delta)

    erase_snake
    move_snake
    collide_snake
    draw_snake
  end

  def move_snake
    if @timer.alarm
      @timer.reset

      if @grow > 0
        @grow -= 1
      else
        @body.pop
      end
      @body.unshift(@body.first.dup)
      
      @body.first[0] += DIRECTION[@direction][0]
      @body.first[1] += DIRECTION[@direction][1]

      @body.first[0] %= @map.width
      @body.first[1] %= @map.height
    end
  end

  def erase_snake
    @body.each do|seg|
      @map[*seg] = :empty
    end
  end

  def collide_snake
    if @body[1..-1].include?(@body.first)
      @status = :dead
    end

    case @map[*@body.first]
    when :wall, :snake
      @status = :dead
    when :apple
      @hungry = true
      grow
    end
  end

  def draw_snake
    @body.each do|seg|
      @map[*seg] = :snake
    end
  end

  def grow(length=3)
    @grow += length
  end

  def growing?
    @grow > 0
  end

  def dead?
    @status == :dead
  end

  def hungry?
    if @hungry
      @hungry = false
      true
    else
      false
    end
  end

  def button_down(id)
    if DIRECTION.keys.include?(id)
      next_head = [
        @body.first[0] + DIRECTION[id][0],
        @body.first[1] + DIRECTION[id][1]
      ]

      unless @body.include?(next_head)
        @direction = id
      end
    end
  end
end

class SnakeGame < Gosu::Window
  module Z
    Background, Tilemap, Text = *1..100
  end

  WIDTH = 640
  HEIGHT = 480
  TITLE = "Snake!"

  TOP_COLOR = Gosu::Color.new(0xFFFFFBE3)
  BOTTOM_COLOR = Gosu::Color.new(0xFF8C865A)
  TEXT_COLOR = Gosu::Color::BLACK

  KEY = {
    '#' => :wall,
    '.' => :empty
  }

  COLORS = {
    :empty => 0xFFFFE4A8,
    :wall  => 0xFF785C11,
    :apple => 0xFFFF0019,
    :snake => 0xFF7CF502
  }

  def initialize
    super(WIDTH, HEIGHT, false)
    self.caption = TITLE

    @tile = Gosu::Image.new(self, 'data/tile.png', true)
    @font = Gosu::Font.new( self, Gosu.default_font_name, 20 )

    if File.exists? 'sounds/eat.ogg'
      @eat_sound = Gosu::Sample.new(self, 'sounds/eat.ogg')
    end

    if File.exists? 'sounds/die.ogg'
      @die_sound = Gosu::Sample.new(self, 'sounds/die.ogg')
    end

    if File.exists? 'sounds/levelup.ogg'
      @levelup_sound = Gosu::Sample.new(self, 'sounds/levelup.ogg')
    end

    if File.exists? 'sounds/music.ogg'
      @music = Gosu::Song.new(self, 'sounds/music.ogg')
      @music.play(true)
    end

    new_game
  end

  def new_game
    @level = 0
    @paused = false

    next_level
  end

  def next_level
    @level += 1
    @level = 1 unless File.exists?("data/level#{@level}.txt")

    if @levelup_sound && @level > 1
      @levelup_sound.play
    end

    @map = Tilemap.new( "data/level#{@level}.txt", KEY )

    new_apple

    @snake = Snake.new(@map)
    @apples = @level * 10
    @pause_timer = Timer.new(3.0)
  end

  def new_apple
    x = Gosu::random(1, @map.width - 1)
    y = Gosu::random(1, @map.height - 1)

    if @map[x, y] == :empty
      @map[x, y] = :apple
    else
      new_apple
    end
  end



  def calculate_delta
    @last_frame ||= Gosu::milliseconds
    @this_frame = Gosu::milliseconds
    @delta = (@this_frame - @last_frame) / 1000.0    
    @last_frame = @this_frame
  end

  def update
    calculate_delta

    @pause_timer.update(@delta)
    return if @paused || !@pause_timer.alarm

    @snake.update(@delta)

    if @snake.hungry?
      @apples -= 1
      @eat_sound.play if @eat_sound && @apples >= 1

      if @apples == 0
        next_level
      else
        new_apple
      end
    end

    if @snake.dead?
      @die_sound.play if @die_sound
      new_game
    end
  end



  def draw
    draw_background
    draw_tilemap
    draw_text
  end

  def draw_tilemap
    left = (WIDTH - (@map.width * @tile.width) ) / 2
    top = (HEIGHT - (@map.height * @tile.height) ) / 2

    (0...@map.width).each do|x|
      (0...@map.height).each do|y|
        @tile.draw(
          left + x * @tile.width,
          top + y * @tile.height,
          Z::Tilemap,
          1.0, 1.0,
          COLORS[@map[x,y]]
        )
      end
    end
  end

  def draw_background
    draw_quad(
      0,     0,      TOP_COLOR,
      WIDTH, 0,      TOP_COLOR,
      0,     HEIGHT, BOTTOM_COLOR,
      WIDTH, HEIGHT, BOTTOM_COLOR,
      Z::Background)
  end

  def draw_text
    @font.draw(
      "Apples: #{@apples}",
      @tile.width * 3,
      @tile.height / 2,
      Z::Text,
      1.0, 1.0,
      TEXT_COLOR
    )

    @font.draw(
      "Level: #{@level}",
      WIDTH - @tile.width * 8,
      @tile.height / 2,
      Z::Text,
      1.0, 1.0,
      TEXT_COLOR
    )

    text_width = @font.text_width("Get ready!!")

    @font.draw(
      "Get ready!!",
      (WIDTH / 2) - (text_width / 2),
      (HEIGHT / 2) - 10,
      Z::Text,
      1.0, 1.0,
      TEXT_COLOR
    ) unless @pause_timer.alarm
  end


  def button_down(id)
    case id
    when Gosu::KbEscape
      close
    when Gosu::KbSpace
      @paused = !@paused
    when Gosu::KbN
      next_level
    end

    @snake.button_down(id)
  end
end

SnakeGame.new.show
