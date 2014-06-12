#
# http://tankionline.com#friend=FASLPW7G4wuCP0EMI16PG5aQ5ycMmYZqV5l0CS59R5prh9JLcdqcrf5XczAS0xfy
# http://tankionline.com/battle-en50.html#friend=FASLPW7G4wuCP0EMI16PG5aQ5ycMmYZqV5l0CS59R5prh9JLcdqcrf5XczAS0xfy

module TankiOnline
  require 'date'

  class << self
    def ParseStat
      db = Hash.new { |hash, key| hash[key] = {} }
      db_last = {}
      res = Hash.new { |hash, key| hash[key] = 0 }
      res_c = Hash.new { |hash, key| hash[key] = 0 }
      res_d = Hash.new { |hash, key| hash[key] = Hash.new { |h2, k2| h2[k2] = 0 } }
      res_wd = Hash.new { |hash, key| hash[key] = Hash.new { |h2, k2| h2[k2] = 0 } }
      res_sup = Hash.new { |hash, key| hash[key] = 0 }
      fn = 'to_gifts.log'
      File.readlines(fn).each do |line|
        line.strip!
        next if line.empty?
        next if ((line[0] == '#') || (line[0] == ';'))
        values = line.strip.split(', ')
        user = values[0].strip
        date = _date(values[1].strip) # bignum?
        hp = values[2].strip.to_i
        cry = values[3].strip.to_i
        gift = values[4].strip
        gift_orig = gift
        if !gift.empty? && (hp >= 1500 || db.has_key?(user)) && gift != 'EXP'
          # add to stat
          gift = _gift(gift)
          if db_last.has_key? user
            dprev = db_last[user][:date]
            gprev = db_last[user][:gift]
          else
            dprev = nil
            gprev = nil
          end

          ds = _day_skipped? date, dprev
          if ds
            #puts "Skipped day #{date} #{dprev}"
            dprev = nil
            gprev = nil
          end

          dv = db_last.has_key? user
          l24 = _less_than_24h? date, dprev
          m24 = _more_than_24h? date, dprev
          u24 = !l24 && !m24
          wd = date.cwday

          #puts "%s %s/%s %s %s %s" % [user, date, dprev, hp, cry, gift] if u24
          l = "#{dv ? (db_last[user][:gift] == :dcc ? 'D' : (db_last[user][:gift] == :cry ? 'C' : (db_last[user][:gift] == :pro ? 'P' : (db_last[user][:gift] == :exp ? 'E' : '.')))) : '?'}"
          t = "#{l24 ? 'L' : (m24 ? 'M' : 'U')}"
          m = "#{dv ? 'V' : '.'}#{ds ? 'S' : '.'}#{t}#{l}-#{gift}"
          res[m] += 1 # if l == '.'

          if dv && !ds
            last_gift = db_last[user][:gift]
            case last_gift
            when :exp, :pro
              res_c[gift] += 1 if m24
              res_wd[wd][gift] += 1 if m24
              res_d[last_gift][gift] += 1 if l24 # another counter in case if less
            when :dcc
              res_d[:dcc][gift] += 1 # another counter
              #res_d["dcc#{t}"][gift] += 1 # another counter
            when :cry, :sup
              res_c[gift] += 1
              #res_c["#{gift}#{wd}".to_sym] += 1
              res_wd[wd][gift] += 1
            else
              raise "Error"
            end
          end

          res_d[:any][gift] += 1
          #res_d[:any]["#{gift}#{wd}".to_sym] += 1
          if hp >= 3700 && gift == :sup
            _gift_sup(gift_orig).each { |g|
               res_sup[g] += 1
            }
          end

          # update db
          db[user][date] = { :hp => hp, :cry => cry, :gift => gift }
          db_last[user] = { :date => date, :hp => hp, :cry => cry, :gift => gift }
        else
          #puts "%s %s %s %s %s" % [user, date, hp, cry, gifts]
        end
      end
      #puts res.select {|c| !c.include?('S') && !c.include?('Uu') && !c.include?('?') }.sort.inspect
      sum = res_c[:cry] + res_c[:exp] + res_c[:pro] + res_c[:sup] + res_c[:dcc]
      res_c.sort.each { |m|
        k = m[0]
        v = m[1]
        puts "#{k} = #{'%5d' % v} (#{'%6.3f' % (v.to_f / sum * 100)} of #{sum})" 
      }
      res_d.each_pair { |ka, va| 
        puts "After #{ka}"
        suma = va[:cry] + va[:exp] + va[:pro] + va[:sup] + va[:dcc]
        va.sort.each { |m|
          k = m[0]
          v = m[1]
          puts "#{k} = #{'%5d' % v} (#{'%6.3f' % (v.to_f / suma * 100)} of #{suma})" 
        }
      }
=begin
      res_wd.each_pair { |ka, va| 
        puts "After #{ka}"
        suma = va[:cry] + va[:exp] + va[:pro] + va[:sup] + va[:dcc]
        va.sort.each { |m|
          k = m[0]
          v = m[1]
          puts "#{k} = #{'%5d' % v} (#{'%6.3f' % (v.to_f / suma * 100)} of #{suma})" 
        }
      }
=end
      puts res_sup.inspect

      # go 
    end

    private

    def _date date
      DateTime::strptime(date.to_s, '%Y%m%d%H%M%S')
    end

    def _more_than_24h? dnew, dold
      return true if (dold.nil? || dnew.nil?)
      dnew - dold > 1.001
    end

    def _less_than_24h? dnew, dold
      return false if (dold.nil? || dnew.nil?)
      dnew - dold < 0.999
    end

    def _day_skipped? dnew, dold
      return false if (dold.nil? || dnew.nil?)
      d2 = Date.new(dnew.year, dnew.month, dnew.mday)
      d2 -= 1 if dnew.hour <= 4
      d1 = Date.new(dold.year, dold.month, dold.mday)
      d1 -= 1 if dold.hour <= 4
      d2 - d1 >= 2
    end

    def _gift gift
      case gift
      when 'DCC'
        out = :dcc
      when 'CRY'
        out = :cry
      when 'PRO'
        out = :pro
      when 'EXP'
        out = :exp
      else
        out = :sup
      end
      out
    end

    def _gift_sup gift
      out = []
      gifts = gift.split(':')
      gifts.each { |g|
        out << g.strip
        out << "#{g.strip}#{gifts.length}"
      }
      out
    end

  end
end

TankiOnline.ParseStat
