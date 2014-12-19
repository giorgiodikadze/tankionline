
module TankiOnline
  class Forum
    require 'net/http'
    require 'uri'

    def load_users fn='forum_info'
      out = []
      lines = File.readlines(fn)
      lines.shuffle!
      lines.each do |line|
        line.strip!
        next if line.empty?
        next if ((line[0] == '#') || (line[0] == ';'))
        values = line.strip.split(':')
        out << values
      end
      out
    end

    def do_req *args
    end

    def rating params = {}
      locale = params.fetch(:locale, 'ru')
      user_file = params.fetch(:user_file, 'forum_info')
      msg_id = params.fetch(:msg_id, 5254001)
      rating = params.fetch(:rating, 1) # might be -1
      users = load_users(user_file)
      c = 0
      #puts users.size
      users.each do |v|
        name = v[0]
        loc = v[1]
        next if locale.to_s != loc.to_s
        member_id = v[2]
        pass_hash = v[3]
        key = v[4]

        puts "#{name} - #{loc} - #{member_id} - #{pass_hash} - #{key}"
        uri = URI.parse("http://#{locale}.tankiforum.com/index.php?app=core&module=global&section=reputation&do=add_rating&app_rate=forums&type=pid&type_id=#{msg_id}&rating=#{rating}&secure_key=#{key}&post_return=#{msg_id}")
        req = Net::HTTP::Get.new(uri.request_uri)
        req['Cookie'] = "t#{loc}_member_id=#{member_id}; t#{loc}_pass_hash=#{pass_hash}"
        req['User-Agent'] = 'Mozilla/5.0 (Linux; Android 4.0.4; Galaxy Nexus Build/IMM76B) AppleWebKit/535.19 (KHTML, like Gecko) Chrome/18.0.1025.133 Mobile Safari/535.19'
        #puts req.to_hash
        #puts req.inspect
        http = Net::HTTP.new(uri.host, uri.port)
        #http.set_debug_output($stdout)
        response = http.request(req)
        puts response.inspect
        #puts response.body
        c += 1
      end
      puts "Done #{c} users"
    end
  end
end


                                                                                                                                                                                                            
#http://ru.tankiforum.com/index.php?app=core&module=global&section=reputation&do=add_rating&app_rate=forums&type=pid&type_id=5254001&rating=1&secure_key=af8a153c07d4450daf64008ff859ae21&post_return=5254001

TankiOnline::Forum.new.rating :rating => -1, :msg_id => 5232385