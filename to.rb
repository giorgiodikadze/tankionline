#
# http://tankionline.com#friend=FASLPW7G4wuCP0EMI16PG5aQ5ycMmYZqV5l0CS59R5prh9JLcdqcrf5XczAS0xfy
# http://tankionline.com/battle-en50.html#friend=FASLPW7G4wuCP0EMI16PG5aQ5ycMmYZqV5l0CS59R5prh9JLcdqcrf5XczAS0xfy

module TankiOnline
  require 'logger'
  require 'watir-webdriver'
  require 'chunky_png_subimage'
  require 'oily_png'
  require 'auto_click'
  require 'openssl'

  class CollectGifts
    URL_MASK = "http://tankionline.com/battle-%s%d.html"
    URL_MASK_BR = "http://tankionline.com.br/battle-%s%d.html"
    URL_MASK_CN = "http://3dtank.com/battle-%s%d.html"

    def initialize params={}
      # parse parameters
      @serverNum = params.fetch(:server_num, 40)
      @serverLocale = params.fetch(:server_locale, "en")
      @logName = params.fetch(:log_name, "to_full.log")
      @url = URL_MASK % [@serverLocale, @serverNum]
      @winResize = params.fetch(:win_resize, nil)
      @emptyScreenshot = params.fetch(:empty_screenshot, false)

      # start browser
      @br = Watir::Browser.new :chrome, :switches => %w[--ignore-certificate-errors --disable-popup-blocking --disable-translate]
      @win = @br.window
      if @winResize.is_a?(Array) and @winResize.size == 2
        @win.resize_to @winResize[0], @winResize[1]
      else
        @win.maximize
      end
      @winSize = @win.size
      @winPos = @win.position

      # other params
      @crypter = OpenSSL::Cipher.new 'AES-128-CBC'
      @logger = Logger.new @logName
      @logger.info "Started"
      @logins = {}
      @subimages_gift = _load_subimages "gift", ["pro", "cry", "dcc", "exp", "da", "dd", "mine", "nitro", "aid"]
      @subimages_char = _load_subimages "chr", ["sep", "colon", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
    end

    def finish
      _combine_statuses
      @br.close
    end

    def collect user, password, params = {}
      @logger.warn "Collect for user: #{user}"
      _goto_login params
      @logger.debug "Wait login page"
      wl = _wait_login
      return unless wl
      @logger.debug "Switch to existing login"
      _switch_existing_login
      @logger.debug "Enter user data"
      _enter_login_data user, password
      @logger.debug "Wait main page ready"
      wm = _wait_main_page

      @logger.debug "Do popup screenshots"
      gifts = []
      img = nil
      while wm && (img = _screenshot_chunky) && _check_main_page_popup?(img) do
        gift = _img_get_gift img
        unless gift.empty?
          _screenshot_save user, img, 'gift'
          gifts += gift
        else
          @logger.debug "No gift found"
          _screenshot_save user, img, 'nongift'
        end
        key_stroke 'enter'
        _sleep 1.5 # to change timestamp also
        @logger.debug "Popup handled"
      end

      st = false # status is parsed
      unless img.nil?
        _screenshot_status_save(user, img)
        xp = _img_get_xp(img)
        cry = _img_get_cry(img)
        st = true unless (xp.nil?  && cry.nil?)
        date = DateTime.now.strftime('%Y%m%d%H%M%S')
        filename = File.expand_path(File.join(File.dirname(__FILE__), 'to_collect.log'))
        File.open(filename, 'a') do |file|
          file.puts "#{user}, #{date}, #{xp}, #{cry}, #{gifts.join(':').upcase}"
        end
        filename = File.expand_path(File.join(File.dirname(__FILE__), 'to_gifts.log'))
        File.open(filename, 'a') do |file|
          file.puts "#{user}, #{date}, #{xp}, #{cry}, #{gifts.join(':').upcase}"
        end unless gifts.empty?
        puts "#{user}, #{date}, xp #{xp}, cry #{cry}, gifts #{gifts.join(':').upcase}"
      end
      _screenshot_save(user) if (@emptyScreenshot && !@logins.fetch(user, nil))

      @logger.debug "Logout"
      _logout
      @logger.debug "Collect - finished (#{wl}, #{wm}, #{st})"

      @logins[user] = true if (wm && wl && st)
    end

    # collect user list from file
    def collect_all fn
      @logger.warn "Collect users from file: #{fn}"
      current_num = 1
      File.readlines(fn).shuffle.each do |line|
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
        puts "User: #{user} (#{current_num})"
        current_num += 1
        collect user, p, params
      end
    end

    def en
      p = _encrypt_pwd 'abc', '123456'
      puts p
      puts _decrypt_pwd 'abc', p
    end

    def i img
      #_img_get_gift img
      #[_img_get_xp(img), _img_get_cry(img)]
      r = [_img_get_xp(img), _img_get_cry(img)]
      _img_status_read_prepare(img).save('st.png')
      r
      #_img_status_read_prepare(_img_get_status img, :both)
      #puts _find_subimages(img, @subimages_gift).inspect
      #puts _find_subimages(img, @subimages_rank).inspect
    end

    private

    # sleep with some randomness
    def _sleep t, d = 0.2
      sleep t * (1 - d / 2 + d * Random.rand(1))
    end

    def _get_url params
      locale = params.fetch(:locale, @serverLocale)
      case locale
      when 'br'
        URL_MASK_BR % ['', 1]
      when 'cn'
        URL_MASK_CN % ['', 1]
      else
        @url
      end
    end

    # broser to go to login page
    def _goto_login params
      @br.goto _get_url(params)
      @br.wait
      _sleep 1 # wait to ensure Flash has changed the page
    end

    def _wait_login
      # login page has white pixels in the middle
      _try_wait(180, 1) {
         _img_check(_screenshot_chunky, 34, 66, 34, 66) { |c|
           c == ChunkyPNG::Color::WHITE
         }
      }
    end

    def _switch_existing_login
      x = @winSize.width / 2 + @winPos.x
      y2 = @winSize.height * 1 / 2 + @winPos.y
      y1 = @winSize.height * 1 / 3 + @winPos.y
      y2.step(y1, -8) { |y|
        #puts "#{x}, #{y}"
        mouse_move x, y
        left_click
      }
      _sleep 1.4 # wait some time to ensure login dialog will be show
    end

    def _enter_login_data user, password
      x = @winSize.width / 2 + @winPos.x
      y = @winSize.height * 1 / 3 + @winPos.y
      mouse_move x, y
      left_click
      sleep 0.1
      key_stroke 'tab'
      type user.to_s
      key_stroke 'tab'
      type password.to_s
      key_stroke 'enter'
    end

    def _wait_main_page
      # login page has white
      _try_wait(150, 1) {
         _img_check(_screenshot_chunky, 75, 100, 34, 66) { |c|
           c == ChunkyPNG::Color::WHITE || c == ChunkyPNG::Color.rgb(127, 127, 127)
         }
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

    def _logout
      # logout
      key_stroke 'esc'
      _sleep 1
      key_stroke 'enter'
      _sleep 3
      @br.wait
    end

    def _screenshot_file user, show_date = true, subfolder = "", folder = "screenshots"
      date = DateTime.now.strftime('%Y%m%d%H%M%S')
      file = folder
      file += "/#{subfolder}" if subfolder.length > 0
      file += "/#{user}"
      file += "_#{date}" if show_date
      file = File.expand_path(file)
    end

    def _screenshot_save user, img = nil, subfolder = ""
      fn = _screenshot_file(user, true, subfolder)
      _img_get_popup(img).save("#{fn}.png") if img
      #@br.screenshot.save "#{fn}.png"
      @logger.warn "Screenshot '#{fn}' is saved"
    end

    def _screenshot_status_save user, img
      fn = _screenshot_file(user, false, "status")
      _img_get_status(img).save("#{fn}.png")
      #w = img.width - 500
      #w = img.width / 2 if w < img.width / 2
      #img.crop(0, 0, w, 32).save("#{fn}.png")
      @logger.warn "Screenshot status '#{fn}' is saved"
    end

    def _screenshot_chunky
      ChunkyPNG::Image.from_blob @br.screenshot.png
    end

    def _combine_statuses
      dir = File.dirname(_screenshot_file('_', false, "status"))
      list = Dir.entries(dir).select {|entry| !File.directory? File.join(dir, entry) and !(entry =='.' || entry == '..') and File.extname(entry) == '.png'}
      images = []
      list.each do |f|
        fn = File.join(dir, f)
        img = ChunkyPNG::Image.from_file(fn)
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
      xc = w / 3
      # find status bar
      while ya < 50 && ya < h do
        c = img.get_pixel(xc, ya)
        break if ChunkyPNG::Color.grayscale?(c) && ChunkyPNG::Color.a(c) == 255 && ChunkyPNG::Color.r(c) > 96
        ya += 1
      end
      yb = ya + 10
      while yb < 64 && yb < h do
        c = img.get_pixel(xc, yb)
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
      @logger.debug "Popup #{xa},#{ya},#{xb},#{yb}"
      #d = 5
      #ya -= d - 1
      #yb += d
      img.crop(xa, ya, xb - xa,  yb - ya)
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

    def _load_subimages prefix, list
      out = {}
      # 
      list.each do |item|
        file = File.expand_path(File.join(File.dirname(__FILE__), 'res', "#{prefix}_#{item}.png"))
        out[item] = ChunkyPNG::Image.from_file(file)
      end
      out
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
      data = _find_subimages img, @subimages_char, true, nil
      #puts data.inspect
      data.each_slice(2) do |p|
        c = p[0]
        c = '/' if c == 'sep'
        c = ':' if c == 'colon'
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
      data = _find_subimages img, @subimages_gift, true
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

t = TankiOnline::CollectGifts.new :server_num => 50, :server_locale => 'en', :win_resize => [1024 + 16, 768], :empty_screenshot => false

# do more than once to prevent random errors
if ARGV.length > 0 && File.exists?(ARGV[0]) && !File.directory?(ARGV[0])

for i in 1..10
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
