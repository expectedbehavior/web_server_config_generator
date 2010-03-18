module WebServerConfigGenerator
  class Pathname < ::Pathname
    def +(other)
      other = self.class.new(other) unless self.class === other
      self.class.new(plus(@path, other.to_s))
    end

    def mkpath
      if $TEST_MODE
        puts "test mode: mkpath #{self}"
      else
        super
      end
    end
    
    def write(arg)
      if $TEST_MODE
        puts "test mode: write #{self}, #{arg.to_s[0, 100]}..."
      else
        FileUtils.mkdir_p File.dirname(self)
        self.open("w") { |f| f.write arg }
      end
    end
    
    def read
      if self.exist?
        self.open("r") { |f| f.read }
      else
        ""
      end
    end
  end
end
