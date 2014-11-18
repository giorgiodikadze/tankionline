#
# http://tankionline.com#friend=FASLPW7G4wuCP0EMI16PG5aQ5ycMmYZqV5l0CS59R5prh9JLcdqcrf5XczAS0xfy
# http://tankionline.com/battle-en50.html#friend=FASLPW7G4wuCP0EMI16PG5aQ5ycMmYZqV5l0CS59R5prh9JLcdqcrf5XczAS0xfy

require 'ffi'
module User32
  extend FFI::Library
  ffi_lib 'user32'
  attach_function :SetCapture,
    :SetCapture, [:uint], :uint
  attach_function :ReleaseCapture,
    :ReleaseCapture, [:uint], :bool
  attach_function :SendMessage,
    :SendMessageA, [:uint, :uint, :uint, :uint], :uint
end

begin
  require_relative 'vk'
rescue LoadError
  puts "Missing VK config"
end

module TankiOnline
  require 'logger'
  require 'watir-webdriver'
  require 'chunky_png_subimage'
  require 'oily_png'
  require 'openssl'
  require 'rautomation'
  require 'thread'

  class << self
    def _load_subimages prefix, list
      out = {}
      # 
      list.each do |item|
        if item.is_a? Hash
          #puts item.to_a.inspect
          name = item.to_a[0][0]
          char = item.to_a[0][1]
        else
          name = item
          char = item
        end
        file = File.expand_path(File.join(File.dirname(__FILE__), 'res', "#{prefix}_#{name}.png"))
        out[char] = ChunkyPNG::Image.from_file(file) #if File.file?(file)
=begin
        list2 = Dir.entries(fp).select {|entry| !File.directory? File.join(fp, entry) and !(entry =='.' || entry == '..') and File.extname(entry) == '.png'}
    list.each do |f|
      fn = File.join(fp, f)
      image = ChunkyPNG::Image.from_file(fn)
      #ud = /^(\S+)_(\d{10,14})/.match(f)
      #puts ud.inspect
      puts "#{fn}: #{t.i(image).inspect}"
    end
=end
      end
      out
    end
  end

  class Browser
    URL_MASK = {
      :default => "http://tankionline.com/battle-%s.html#/server=%s%d",
      :br => "http://tankionline.com.br/battle.html#/server=PT%d",
      :cn => "http://3dtank.com/battle-%s%d.html"
    }
    SUBIMAGES = {
      :gift => TankiOnline::_load_subimages("gift", ["pro", "cry", "dcc", "exp", "da", "dd", "mine", "nitro", "aid"]),
      :char => TankiOnline::_load_subimages("chr", [{"sep" => "/"}, {"colon" => ":"}, "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]),
      :vk_ready => TankiOnline::_load_subimages("vk", ["gift_cry", "icon_friends"]),#, "icon_friends_dark"]),
    }
    WAIT_LOGIN_PAGE_STARTED = 1
    WAIT_LOGIN_PAGE_LOADED = 60*3
    WAIT_LOGIN_DIALOG_SWITCHED = 1.4
    WAIT_LOGIN_BY_VK = 1.5
    WAIT_LOGIN_IN_VK_LOADED = 90
    WAIT_MAIN_PAGE_LOADED = 150
    WAIT_POPUP_CLOSE = 1.5
    WAIT_LOGOUT_ESC = 1
    WAIT_LOGOUT_ENTER = 3
    WAIT_LOGOUT_BROWSER_IDLE = 5

    #
    @@mutexScreenshot = Mutex.new
    @@mutexFile = Mutex.new
    @@mutexMouse = Mutex.new
    @@mutexKeys = Mutex.new

    #
    attr_reader :user
    attr_reader :status
    attr_reader :mode

    def initialize params={}
      # parse parameters
      @serverNum = params.fetch(:server_num, 40)
      @serverLocale = params.fetch(:server_locale, "en")
      @serverTarget = params.fetch(:server_target, "RU")
      @logName = params.fetch(:log_name, "log/to_browser_#{DateTime.now.strftime('%Y%m%d%H%M%S%L')}.log")
      @winResize = params.fetch(:win_resize, nil)
      @winMove = params.fetch(:win_move, nil)
      @emptyScreenshot = params.fetch(:empty_screenshot, false)
      @vkInitialized = false

      # other params
      @logger = Logger.new @logName
      @logger.info "Started"

      # browser instance
      _init_browser

      # set initial status
      _change_status :idle
    end

    def finish
      @br.close if @status != :closed
      @user = nil

      _change_status :closed
    end

    def idle?
      status == :idle
    end

    def collect user, password, params = {}
      raise "Not idle" unless idle?

      # if retry
      _reset_browser if user == @user

      # prepare environment
      @mode = params.fetch(:mode, :collect)
      _clear_user_data
      _init_user_data user, password, params

      _change_status :login

      @logger.info "Start to do '#{mode}' for user: #{user}"
    end

    def step
      #@logger.debug "Current status: #{@status}"
      next_status = nil

      case @status
      when :login
        # login to VK if needed
        _login_vk(VK_LOGIN, VK_PWD) if ((mode == :vk_add || mode == :vk_remove) && !@vkInitialized)

        # browser to go to login page
        @br.goto _get_login_url(@userParams)
        next_status = :login_page_wait
      when :login_page_wait
        # wait page will be ready
        next_status = :login_page_wait2 if _browser_ready?
      when :login_page_wait2
        # prepare to wait more (to ensure Flash has changed the page)
        next_status = _wait_step(:login_dialog_wait, WAIT_LOGIN_PAGE_STARTED)
      when :login_dialog_wait
        # wait login dialog to appear
        _wait_init WAIT_LOGIN_PAGE_LOADED
        next_status = :login_dialog_wait2
      when :login_dialog_wait2
        @screenshot = _screenshot_chunky
        next_status = :login_dialog_wait3
      when :login_dialog_wait3
        r = _img_check(@screenshot, 34, 66, 34, 66) { |c|
           c == ChunkyPNG::Color::WHITE
        }
        if r
          next_status = :login_switch
        elsif _wait_done?
          next_status = :abort
        else
          next_status = :login_dialog_wait2
        end
      when :login_switch
        _switch_existing_login
        if mode == :vk_remove
          next_status = _wait_step(:login_by_vk, WAIT_LOGIN_DIALOG_SWITCHED)
        else
          next_status = _wait_step(:login_enter_data, WAIT_LOGIN_DIALOG_SWITCHED)
        end
      when :login_by_vk
        _click_login_vk
        next_status = _wait_step(:main_page_wait, WAIT_LOGIN_BY_VK)
      when :login_enter_data
        _click_mouse @winSize.width / 2, @winSize.height * 1 / 3
        next_status = _wait_step(:login_enter_data_2, 0.1)
      when :login_enter_data_2
        _send_keys :tab
        next_status = _wait_step(:login_enter_data_3, 0.1)
      when :login_enter_data_3
        _send_keys @user.to_s
        next_status = _wait_step(:login_enter_data_4, 0.3)
      when :login_enter_data_4
        _send_keys :tab
        _sleep 0.1
        next_status = _wait_step(:login_enter_data_5, 0.3)
      when :login_enter_data_5
        _send_keys @userPassword.to_s
        _sleep 0.4
        next_status = _wait_step(:login_enter_data_6, 0.5)
      when :login_enter_data_6
        _send_keys :enter
        _sleep 0.5
        next_status = :main_page_wait
      when :main_page_wait
        _wait_init WAIT_MAIN_PAGE_LOADED
        next_status = :main_page_wait2
      when :main_page_wait2
        @screenshot = _screenshot_chunky
        next_status = :main_page_wait3
      when :main_page_wait3
        # login page has white
        r = _img_check(@screenshot, 75, 100, 34, 66) { |c|
          c == ChunkyPNG::Color::WHITE || c == ChunkyPNG::Color.rgb(127, 127, 127)
        }
        if r
          next_status = :main_page_ready
        elsif _wait_done?
          next_status = :abort
        else
          next_status = :main_page_wait2
        end
      when :main_page_ready
        @userGiftsDate ||= DateTime.now.strftime('%Y%m%d%H%M%S')
        if _check_main_page_popup?(@screenshot)
          next_status = :main_page_handle_popup
        else
          next_status = :main_page_no_popups
        end
      when :main_page_handle_popup
        _handle_popup @screenshot
        next_status = :main_page_next_popup
      when :main_page_next_popup
        _send_keys :enter
        next_status = _wait_step(:main_page_next_popup3, WAIT_POPUP_CLOSE)
      when :main_page_next_popup3
        @screenshot = _screenshot_chunky
        next_status = :main_page_ready
      when :main_page_no_popups
        _parse_status @screenshot
        case mode
        when :vk_add, :vk_remove
          next_status = :open_settings
        else
          next_status = :logout
        end
      when :open_settings
        _sleep 5
        _click_mouse 919, 91
        next_status = _wait_step(:vk_button, 1)
      when :vk_button
        _sleep 2
        _click_mouse 450, 520
        next_status = _wait_step(:vk_button_ready, 1)
      when :vk_button_ready
        if mode == :vk_add
          next_status = :vk_add_login
        else
          _sleep 1
          _send_keys :enter # close 'vk linked' popup
          _sleep 0.5
          _send_keys :enter # close settings
          _sleep 0.5
          next_status = :logout
        end
      when :vk_add_login
        sleep 5
        win = @br.window(:title, "VK | Login")
        if win.exists?
          win.use do
            @br.text_field(:name, "email").set(VK_LOGIN)
            @br.text_field(:name, "pass").set(VK_PWD)
            @br.button(:text, "Log in").click
          end
        else
          puts 'Should be autolinked...'
        end
        @br.wait
        _sleep 3
        _send_keys :enter # close 'vk linked' popup
        _sleep 0.5
        _send_keys :enter # close settings
        _sleep 0.5
        begin
          @br.goto 'http://vk.com/tanki_online'
        rescue
          begin
            @br.goto 'http://vk.com/tanki_online'
          rescue 
            puts "Exception: #{$!}"
          end
        end
        sleep 5
        _wait_init WAIT_LOGIN_IN_VK_LOADED
        next_status = :vk_add_login2
      when :vk_add_login2
        @screenshot = _screenshot_chunky
        if _img_get_vk_ready(@screenshot)
          next_status = :vk_add_login3
        elsif _wait_done?
          next_status = :abort
        else
          next_status = :vk_add_login2
        end
        #@br.wait
        #@br.button(:id, "apps_i_btn").click
        #sleep 40 + 25
      when :vk_add_login3
        sleep 5
        _screenshot_save @user, _screenshot_chunky, "work", false
        @mode = :vk_remove
        next_status = :login
      when :logout
        _send_keys :escape
        next_status = _wait_step(:logout_enter, WAIT_LOGOUT_ESC)
      when :logout_enter
        _send_keys :enter
        next_status = _wait_step(:logout_wait, WAIT_LOGOUT_ENTER)
      when :logout_wait
        next_status = _wait_step(:idle, WAIT_LOGOUT_BROWSER_IDLE) {
          _browser_ready?
        }
      when :wait_do
        next_status = @wait_next_status if _wait_done?
      when :idle
        # do nothing
      when :abort
        _screenshot_save @user, _screenshot_chunky, "errors"
        # clear all data
        _clear_user_data
        next_status = :idle
      else
        raise StandardError, "Unknown status!"
      end
      
      _change_status(next_status) unless next_status.nil?
    end

    def combine_statuses
      _combine_statuses
    end

    def user_done?
      idle? && !@user.nil? && !@userPassword.nil?
    end

    def user_clear
      if idle? and !@user.nil?
        _clear_user_data
        @user = nil
      end
    end

    #private

    #
    def _change_status st
      @logger.debug "Next status: '#{st}'"
      @status = st
    end

    def _clear_user_data
      @userGifts = nil
      @userGiftsDate = nil
      @userXP = nil
      @userCry = nil
      @userPassword = nil
    end

    def _init_user_data user, password, params
      @user = user
      @userPassword = password
      @userParams = params
    end

    def _wait_step next_status, timeWait = 5, &blk
      # init
      @wait = [Time.now, timeWait]
      @wait_next_status = next_status
      @wait_condition = blk

      # return the next step which will do the waiting
      :wait_do
    end

    def _wait_init timeWait
      @wait = [Time.now, timeWait]
    end

    def _wait_time_done?
      Time.now - @wait[0] > @wait[1]
    end

    def _wait_done?
      return true if _wait_time_done?
      return true if @wait_condition.is_a?(Proc) && @wait_condition.call
      false
    end

    def _browser_ready?
      @br.ready_state == "complete"
    end

    def _init_browser
      # start browser
      @logger.debug "Create new browser window"
      switches = %w[--disable-popup-blocking --disable-translate --test-type]
      switches = %w[--disable-popup-blocking --disable-translate --test-type --disk-cache-dir=c:\\tmp\\cache]
      #puts switches.inspect
      @br = Watir::Browser.new :chrome, :switches => switches
      title = "TO" + (0...15).map { ('a'..'z').to_a[rand(26)] }.join
      @br.execute_script "document.title=\"#{title}\";"
      while (@winr = RAutomation::Window.new(:title => /#{Regexp.escape(title)}/)) && !@winr.exists?
        _sleep 0.25
      end
      #puts @winr.exists?
      raise "Cannot find window" unless @winr.exists?
      @win = @br.window
      if @winResize.is_a?(Array) and @winResize.size == 2
        @win.resize_to @winResize[0], @winResize[1]
        @win.move_to(@winMove[0], @winMove[1]) if @winMove.is_a?(Array) and @winMove.size == 2
      else
        @win.maximize
      end
      @winSize = @win.size
      @winPos = @win.position
      @logger.debug "Window size #{@winSize} position #{@winPos}"
    end

    def _reset_browser
      @logger.debug "Reset browser"
      #@br.close
      #_init_browser
    end

    # bring window up
    def _window_up
      #@br.screenshot.png
      #@win.use
      #@win.maximize
      #@win.resize_to(@winSize.width, @winSize.height)
      #@win.move_to(@winPos.x, @winPos.y)
      #@winr.activate
      #_sleep 0.25
    end

    def _login_vk name, pwd
      @br.goto 'http://vk.com/'
      @br.wait
      @br.text_field(:id, "quick_email").set(name)
      @br.wait
      @br.text_field(:id, "quick_pass").set(pwd)
      @br.wait
      @br.button(:id, "quick_login_button").click
      @br.wait
      sleep 2
      @vkInitialized = true
    end

    def _click_mouse x, y
      hwnd = @winr.hwnd
      dw = (x + y * 0x10000).to_i
      @@mutexMouse.synchronize do
        User32.SetCapture(hwnd)
        User32.SendMessage(hwnd, 0x0201, 1, dw);
        User32.SendMessage(hwnd, 0x0202, 1, dw);
        User32.ReleaseCapture(hwnd)
      end
    end

    def _send_key arg
      hwnd = @winr.hwnd
      puts "Send key #{hwnd}: #{arg}"
      if arg < 0x20
        User32.SendMessage(hwnd, 0x0100, arg, 1);
        User32.SendMessage(hwnd, 0x0101, arg, 1);
      else
        User32.SendMessage(hwnd, 0x0102, arg, 1);
      end
    end

    def _send_keys *args
      @br.send_keys *args
=begin
      #@@mutexKeys.synchronize do
      args.each do |cur|
        if cur.is_a? Symbol
          case cur
          when :tab
            _send_key 0x09
          when :enter
            _send_key 0x0d
          when :escape
            _send_key 0x1b
          else
            raise "Unsupported symbol"
          end
        else
          cur.each_char do |c|
            _send_key c.unpack("c")[0]
          end
        end
      end
      _sleep 0.5
=end
    end

    # get screenshot in chunky-png format
    def _screenshot_chunky
      png = nil
      @@mutexScreenshot.synchronize do
        png = @br.screenshot.png
      end
      ChunkyPNG::Image.from_blob png
    end

    def _screenshot_file user, show_date = true, subfolder = "", folder = "screenshots"
      date = DateTime.now.strftime('%Y%m%d%H%M%S')
      file = folder
      file += "/#{subfolder}" if subfolder.length > 0
      file += "/#{user}"
      file += "_#{date}" if show_date
      file = File.expand_path(file)
    end

    def _screenshot_save user, img = nil, subfolder = "", popup_only = true
      fn = _screenshot_file(user, true, subfolder)
      if img
        if popup_only
          popup = _img_get_popup(img)
        else
          popup = img
        end
        popup.save("#{fn}.png") if popup
        @logger.warn "Screenshot '#{fn}' is saved (#{popup.nil?})"
      else
        @logger.warn "Screenshot '#{fn}' is NOT saved"
      end
      #@br.screenshot.save "#{fn}.png"
    end

    def _screenshot_status_save user, img
      fn = _screenshot_file(user, false, "status")
      _img_get_status(img).save("#{fn}.png")
      #w = img.width - 500
      #w = img.width / 2 if w < img.width / 2
      #img.crop(0, 0, w, 32).save("#{fn}.png")
      @logger.warn "Screenshot status '#{fn}' is saved"
    end

    # get the proper url to the login page
    def _get_login_url params
      locale = params.fetch(:locale, @serverLocale)
      case locale
      when 'br'
        URL_MASK[:br] % [1]
      when 'cn'
        URL_MASK[:cn] % ['', 1]
      else
        URL_MASK[:default] % [@serverLocale, @serverTarget, @serverNum]
      end
    end

    def _click_login_vk
      x = @winSize.width * 7 / 16 # + @winPos.x
      y2 = @winSize.height * 3 / 4# + @winPos.y
      y1 = @winSize.height * 1 / 2# + @winPos.y
      y2.step(y1, -8) { |y|
        #puts "#{x}, #{y}"
        _click_mouse x, y
        #mouse_move x, y
        #left_click
      }
    end

    def _switch_existing_login
      x = @winSize.width / 2# + @winPos.x
      y2 = @winSize.height * 1 / 2# + @winPos.y
      y1 = @winSize.height * 1 / 3# + @winPos.y
      y2.step(y1, -8) { |y|
        #puts "#{x}, #{y}"
        _click_mouse x, y
        #mouse_move x, y
        #left_click
      }
    end

    # possible notifications
    def _check_main_page_popup? img
      # check is any popup shown on the main page?
      r = _img_check(img, 75, 100, 34, 66) { |c|
        c == ChunkyPNG::Color::WHITE
      }
      # white should exist if not popup
      !r
    end

    # sleep with some randomness
    def _sleep t, d = 0.2
      sleep t * (1 - d / 2 + d * Random.rand(1))
    end

    # img will be changed
    def _handle_popup img
      @logger.debug "Handle popup"
      gifts = []
      gift = _img_get_gift img
      unless gift.empty?
        @logger.debug "Gift found: #{gift}"
        _screenshot_save @user, img, 'gift'
        gifts += gift
      else
        @logger.debug "No gift found"
        _screenshot_save @user, img, 'nongift'
      end
      @logger.debug "Popup handled"
      unless gifts.empty?
        @userGifts = [] unless @userGifts.is_a?(Array)
        @userGifts += gifts 
      end
    end

    def _parse_status img
      st = false # status is parsed
      unless img.nil?
        _screenshot_status_save(@user, img)
        xp = _img_get_xp(img)
        @userXP = xp
        cry = _img_get_cry(img)
        @userCry = cry
        st = true unless (xp.nil?  && cry.nil?)
        gifts = @userGifts
        gifts = [] if gifts.nil?
        date = @userGiftsDate
        date = DateTime.now.strftime('%Y%m%d%H%M%S') if date.nil?
        @@mutexFile.synchronize do
          filename = File.expand_path(File.join(File.dirname(__FILE__), 'to_collect.log'))
          File.open(filename, 'a') do |file|
            file.puts "#{@user}, #{date}, #{xp}, #{cry}, #{gifts.join(':').upcase}"
          end
          filename = File.expand_path(File.join(File.dirname(__FILE__), 'to_gifts.log'))
          File.open(filename, 'a') do |file|
            file.puts "#{@user}, #{date}, #{xp}, #{cry}, #{gifts.join(':').upcase}"
          end unless gifts.empty?
        end
        puts "#{@user}, #{date}, xp #{xp}, cry #{cry}, gifts #{gifts.join(':').upcase}"
      end
    end

    def _combine_statuses
      dir = File.dirname(_screenshot_file('_', false, "status"))
      list = Dir.entries(dir).select {|entry| !File.directory? File.join(dir, entry) and !(entry =='.' || entry == '..') and File.extname(entry) == '.png'}
      images = []
      images_xp = Hash.new { |h, k| h[k] = [] }
      list.each do |f|
        begin
          fn = File.join(dir, f)
          img = ChunkyPNG::Image.from_file(fn)
          xp = _img_get_xp(img).to_i
          img_s = _img_get_status img, :status
          img_c = _img_get_status img, :cry
          next if img_s.nil? or img_c.nil? or img_s.width < 5 or img_c.width < 5 or img_s.height < 9 or img_c.height < 9
          img_s.crop!(1, 0, img_s.width - 2, img_s.height)
          img_c.crop!(1, 0, img_c.width - 2, img_c.height)
          img_both = ChunkyPNG::Image.new(img_s.width + img_c.width, [img_s.height, img_c.height].max)
          img_both.compose!(img_s, 0, 0)
          img_both.compose!(img_c, img_s.width - 1, 0)
          img = img_both
          img.crop!(2, 3, img.width - 2 - 1, img.height - 3 - 3)
          images << img
          images_xp[xp] << img
        rescue
          puts "Rescued handling #{f}: #{$!}\n#{$@}"
        end
      end
      w = 0
      h = 0
      images.each do |img|
        w = img.width if img.width > w
        h += img.height
      end
      puts "Combined statuses #{w}x#{h}"
      global = ChunkyPNG::Image.new(w, h, ChunkyPNG::Color::TRANSPARENT)
      h = 0
      images.each do |img|
        global.compose!(img, 0, h)
        h += img.height
      end
      global.save('_.png')
      # xp
      global = ChunkyPNG::Image.new(w, h, ChunkyPNG::Color::TRANSPARENT)
      h = 0
      order = images_xp.keys.sort
      order.each do |k|
        arr = images_xp[k]
        arr.each do |img|
          global.compose!(img, 0, h)
          h += img.height
        end
      end
      global.save('__.png')
    end

    # prepare status window for recognition
    def _img_status_read_prepare img
      for x in 0..(img.width - 1)
        for y in 0..(img.height - 1)
          c = img.get_pixel(x, y)
          if ChunkyPNG::Color.r(c) < 32 && ChunkyPNG::Color.b(c) < 32 && ChunkyPNG::Color.g(c) > 128
            img[x, y] = ChunkyPNG::Color::WHITE
          else
            img[x, y] = ChunkyPNG::Color::BLACK
          end
        end
      end
      img
    end

    # get image for the status + crystall bars
    def _img_get_status img, mode = :both
      w = img.width
      h = img.height
      ya = 0
      xc = w / 4
      # find status bar
      while ya < 50 && ya < h do
        c = img.get_pixel(xc, ya)
        break if ChunkyPNG::Color.grayscale?(c) && ChunkyPNG::Color.a(c) == 255 && ChunkyPNG::Color.r(c) > 96
        ya += 1
      end
      yb = ya + 10
      while yb < 64 && yb < h do
        c = img.get_pixel(xc, yb)
        #puts "xc #{xc}, ya #{ya}, yb #{yb}, c #{c}"
        break if ChunkyPNG::Color.grayscale?(c) && ChunkyPNG::Color.a(c) == 255 && ChunkyPNG::Color.r(c) > 96
        yb += 1
      end

      xa = xc - 1
      while xa > 0 do
        c = img.get_pixel(xa, ya)
        break unless ChunkyPNG::Color.grayscale?(c) && ChunkyPNG::Color.a(c) == 255 && ChunkyPNG::Color.r(c) > 96
        xa -= 1
      end
      xb = xc + 1
      while xb < w do
        c = img.get_pixel(xb, ya)
        break unless ChunkyPNG::Color.grayscale?(c) && ChunkyPNG::Color.a(c) == 255 && ChunkyPNG::Color.r(c) > 96
        xb += 1
      end

      if mode == :both || mode == :cry
        # also add crystall window
        # empty space
        while xb < w do
          c = img.get_pixel(xb, ya)
          break if ChunkyPNG::Color.grayscale?(c) && ChunkyPNG::Color.a(c) == 255 && ChunkyPNG::Color.r(c) > 96
          xb += 1
        end

        xa = xb if mode == :cry

        # crystall bar
        while xb < w do
          c = img.get_pixel(xb, ya)
          break unless ChunkyPNG::Color.grayscale?(c) && ChunkyPNG::Color.a(c) == 255 && ChunkyPNG::Color.r(c) > 96
          xb += 1
        end
        xb += 1 unless xb == w
      end

      #puts "#{mode.inspect} #{xa},#{ya},#{xb},#{yb}"
      img.crop(xa, ya, xb - xa,  yb - ya)
    end

    def _img_get_popup img
      w = img.width
      h = img.height
      y = h / 2
      xc = w / 2
      ce = ChunkyPNG::Color.rgb(163, 163, 163)
      xb = 0
      for x in xc..(w-1)
        if (img.get_pixel(x, y) == ce) && (img.get_pixel(x, y - 1) == ce) && (img.get_pixel(x, y + 1) == ce) && (img.get_pixel(x, y - 2) == ce) && (img.get_pixel(x, y + 2) == ce)
          xb = x
          break
        end
      end
      ya = y - 2
      while y > 0 && img.get_pixel(xb, ya) == ce do
        ya -= 1
      end
      yb = y + 2
      while y < h && img.get_pixel(xb, yb) == ce do
        yb += 1
      end
      xa = xc - (xb - xc)
      @logger.debug "Popup #{xa},#{ya},#{xb},#{yb} (img #{w}x#{h})"
      #d = 5
      #ya -= d - 1
      #yb += d
      xw = xb - xa
      yh = yb - ya
      if xa >= 0 && xa < w && ya >= 0 && ya < h && xa + xw > 0 && xa + xw < w && ya + yh > 0 && ya + yh < h
        img.crop(xa, ya, xw,  yh)
      else
        @logger.debug "Popup #{xa},#{ya},#{xb},#{yb} - does not fit to original image"
        nil
      end
    end

    def _img_check img, wfa, wfb, hfa, hfb, &blk
      # conditions check
      wf = [0, wfa, wfb, 100].sort
      wfa = wf[1].to_f / 100
      wfb = wf[2].to_f / 100
      hf = [0, hfa, hfb, 100].sort
      hfa = hf[1].to_f / 100
      hfb = hf[2].to_f / 100
 
      # initial data
      w = img.width
      h = img.height
      xa = (w * wfa).to_i
      xb = (w * wfb).to_i
      ya = (h * hfa).to_i
      yb = (h * hfb).to_i

      #@logger.debug "Check #{xa} #{xb} #{ya} #{yb}"
      r = false
      for y in ya..(yb - 1)
        for x in xa..(xb - 1)
          c = img.get_pixel(x, y)
          r = blk.call(c)
          #@logger.debug "Check coord #{x} #{y} color #{c} r #{r}"
          break if r
        end
        break if r
      end
      r
    end

    # try to do block with auto sleeps
    def _try_wait tries = 30, wait = 0.5, &blk
      r = false
      for i in 1..tries
        r = blk.call
        break if r
        _sleep wait unless i == tries
      end
      r
    end

    def _find_subimages img, subimages, with_coords = false, single = :single_same_subimage
      out = []
      keys = []
      si = []

      subimages.each_pair do |k, v|
        keys << k
        si << v
        #puts v.dimension.inspect
      end
      #puts "Search for: #{keys.inspect}"

      r = ChunkyPNGSubimage::search_subimage(img, si, single)
      r.each_with_index do |a, i|
        out << keys[i] unless a.empty?
        out << a if (with_coords && !a.empty?)
      end
      out
    end

    def _recognize_text img
      chrs = {}
      data = _find_subimages img, SUBIMAGES[:char], true, nil
      #puts data.inspect
      data.each_slice(2) do |p|
        c = p[0]
        a = p[1]
        a.each do |t|
          k = t[0]
          kp = t[0] - 1 # key prev
          kn = t[0] + 1 # key next
          if chrs.has_key?(k) && chrs[k] == c
            @logger.debug "Same place char, #{t} / #{data.inspect}"
          elsif (chrs.has_key?(kn) && chrs[kn] == c) || (chrs.has_key?(kp) && chrs[kp] == c)
            @logger.debug "Near character, #{t} / #{data.inspect}"
          else
            chrs[t[0]] = c
          end
        end
        #@logger.debug data.inspect
      end
      #puts chrs.sort.map { |k, v| v.to_s }.join
      chrs.sort.map { |k, v| v.to_s }.join.split(/[\/:]/)[0]
    end

    def _img_get_xp img
      ti = _img_status_read_prepare(_img_get_status img, :status)
      #ti.save 'st.png'
      _recognize_text(ti)
    end

    def _img_get_cry img
      ti = _img_status_read_prepare(_img_get_status img, :cry)
      #ti.save 'cry.png'
      _recognize_text(ti)
    end

    def _img_get_gift img
      gifts = {}
      data = _find_subimages img, SUBIMAGES[:gift], true
      # handle to be sure that the order is a proper one
      data.each_slice(2) do |p|
        c = p[0]
        a = p[1]
        a.each do |t|
          k = t[0]
          gifts[k] = c
        end
      end
      out = []
      gifts.sort.each do |m| 
        out << m[1]
      end
      out
    end

    def _img_get_vk_ready img
      data = _find_subimages img, SUBIMAGES[:vk_ready], true
      #puts data.inspect
      !data.empty?
    end
  end

  class CollectGifts
    def initialize params={}
      # parse parameters
      @brParams = params
      @maxBrowsers = params.fetch(:max_browsers, 3)
      @logName = params.fetch(:log_name, "log/to_full.log")
      @collectMode = params.fetch(:collect_mode, :collect)

      # start browser
      x0 = 0
      x0 = -224 if @maxBrowsers == 2
      x0 = -768 if @maxBrowsers >= 3
      @brs = []
      @maxBrowsers.times do
        params[:win_move] = [x0, -10] unless params.has_key? :win_move
        @brs << Browser.new(params)
        params[:win_move][0] += 1044
      end

      # other params
      #@crypter = OpenSSL::Cipher.new 'AES-128-CBC'
      @logger = Logger.new @logName
      @logger.info "Started"
      @logins = {}
    end

    def finish
      @brs[0].combine_statuses
      @brs.each do |br|
        br.finish
      end
    end

    def load_users fn
      lines = File.readlines(fn)
      #lines.shuffle!
      lines.each do |line|
        line.strip!
        next if line.empty?
        next if ((line[0] == '#') || (line[0] == ';'))
        values = line.strip.split(':')
        user = values[0].strip
        p = values[1].strip
        params = {}
        params[:email] = values[2].strip if values.length > 2
        params[:locale] = values[3].strip if values.length > 3
        if @logins.fetch(user, nil)
          @logger.warn "Skip '#{user}' as already handled"
          next
        end
        #puts "User: #{user} (#{current_num})"
        @logins[user] = [p, params, 0]
      end
      @logger.debug "Users to load: #{@logins.keys.inspect}"
      @logins
    end

    # collect user list from file
    def collect_all fn
      @logger.warn "Collect users from file: #{fn}"
      load_users fn

      # multithreading
=begin
      thrs = []
      @brs.each do |br|
        thrs << Thread.new {
          loop do
            br.step
            Thread.pass
          end
        }
      end
=end

      while !@logins.empty? do
        @brs.each do |br|
          br.step

          if br.idle? 
            u = br.user
            if br.user_done?
              # delete from the list
              @logins.delete(br.user)
              br.user_clear
              u = nil
            elsif !u.nil?
              # new try
            end

            if u.nil?
              # add new user
              possible = @logins.select { |k, v| v[2] == 0 }
              unless possible.keys.empty?
                u = possible.keys[0]
                p = @logins[u][0]
                params = @logins[u][1]
                params[:mode] = @collectMode
                puts "User: #{u} (#{@logins.length})"
                @logins[u][2] = 1
                @logger.debug "Started #{u}"
                br.collect u, p, params
              end
            else
              # re-try
              @logger.warn "Retry #{u}"
           
              p = @logins[u][0]
              params = @logins[u][1]
              br.collect u, p, params
            end
          end
        end
      end

=begin
      thrs.each do |thr|
        thr.kill
      end
=end

      @logger.warn "Collect users - done"
    end

    def en
      p = _encrypt_pwd 'abc', '123456'
      puts p
      puts _decrypt_pwd 'abc', p
    end

    def i img
      br = @brs.first
      br._img_get_gift img
      #[_img_get_xp(img), _img_get_cry(img)]
      #r = [_img_get_xp(img), _img_get_cry(img)]
      #br._img_status_read_prepare(img).save('st.png')
      #br._img_get_status(img).save("st.png")
      #br._img_get_vk_ready(img)
      #r
      #_img_status_read_prepare(_img_get_status img, :both)
      #puts _find_subimages(img, SUBIMAGES[:gift]).inspect
      #puts _find_subimages(img, @@subimages_rank).inspect
    end

    private

    def _crypt_salt user
      "#{user}#{user}#{user}#{user}#{user}#{user}#{user}#{user}"[0..7]
    end

    def _encrypt_pwd user, password
      @crypter = OpenSSL::Cipher.new 'AES-128-CBC'
      @crypter.encrypt
      @crypter.pkcs5_keyivgen 'pwd', _crypt_salt(user)
      encrypted = @crypter.update password
      encrypted << @crypter.final
      [encrypted].pack("m")
    end

    def _decrypt_pwd user, password
      @crypter = OpenSSL::Cipher.new 'AES-128-CBC'
      @crypter.decrypt
      @crypter.pkcs5_keyivgen 'pwd', _crypt_salt(user)
      plain = @crypter.update password.unpack("m")[0]
      plain << @crypter.final
    end

  end
end

Thread.abort_on_exception = true
#sleep ( 2 * 60 - 15 ) * 60
#t = TankiOnline::CollectGifts.new :server_num => 12, :server_locale => 'ru', :win_resize => [1024 + 16, 768], :max_browsers => 1, :empty_screenshot => false, :collect_mode => :vk_add
#t = TankiOnline::CollectGifts.new :server_num => 40, :server_locale => 'en', :win_resize => [1024 + 16, 768], :max_browsers => 3, :empty_screenshot => false
t = TankiOnline::CollectGifts.new :server_num => 10, :server_locale => 'en', :win_resize => [1024 + 16, 768], :max_browsers => 1, :empty_screenshot => false
#t = TankiOnline::CollectGifts.new :server_num => 3, :server_locale => 'ru', :win_resize => [1024 + 16, 768], :max_browsers => 1, :empty_screenshot => false

# do more than once to prevent random errors
if ARGV.length > 0 && File.exists?(ARGV[0]) && !File.directory?(ARGV[0])

for i in 1..1
  #puts "Step #{i}"
  t.collect_all ARGV[0]
end

elsif ARGV.length > 1 && ARGV[0] == 'i'
  fp = ARGV[1]
  if File.directory? fp
    list = Dir.entries(fp).select {|entry| !File.directory? File.join(fp, entry) and !(entry =='.' || entry == '..') and File.extname(entry) == '.png'}
    list.each do |f|
      fn = File.join(fp, f)
      image = ChunkyPNG::Image.from_file(fn)
      #ud = /^(\S+)_(\d{10,14})/.match(f)
      #puts ud.inspect
      puts "#{fn}: #{t.i(image).inspect}"
    end
    #puts list.inspect
  elsif File.file? fp
    image = ChunkyPNG::Image.from_file(fp)
    puts "#{fp}: #{t.i(image).inspect}"
  else
    puts "Unknown parameter"
  end
else
  puts ARGV[0]
end

t.finish
