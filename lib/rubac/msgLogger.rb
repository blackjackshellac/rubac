
module Rubac
  
  $LOGLEVELS = {  "emerg"  => 0,
      "alert"  => 1,
      "crit"   => 2,
      "err"    => 3,
      "warn"   => 4,
      "notice" => 5,
      "info"   => 6,
      "debug"  => 7 }
  
  class MsgObject
    attr :client, true
    attr_reader :io
  
    def initialize(name, handle, datefmt=nil, sync=false)
      @name = name
      if handle
        @io = handle
      else
        @io = String.new
      end
      @datefmt = datefmt
      @io.sync = true if @io.class == File
  
      @client = "localhost"
      @loglevel = $LOGLEVELS["info"]
    end
  
    def timestamp
      Time.now.strftime(@datefmt) + " " + @client + " "
    end
  
    def << (msg)
      msg.each_line do |line|
        line.chomp!
        @io << timestamp if @datefmt
        @io << line + "\n"
      end
    end
  
    # don't add CR to message
    def print(msg)
      @io << msg
    end
  
    def printf(fmt, *args)
      @io << sprintf(fmt, *args)
    end
  
    def empty
      @io = ""
    end
  end

  class MsgLogger < Logger
    attr_accessor :console
    attr_accessor :syslog
    attr_accessor :privlog
    attr_accessor :notify
    attr_accessor :loglevels
    attr_accessor :loglevel
  
    def initialize(dest=nil)
      me=self.class.name
  
      puts "Init #{me}: #{dest}" if @debug
  
      @loglevel = $LOGLEVELS["info"]
  
      @console = nil
      @syslog = nil 
      @privlog = nil
      @notify = nil
      @email = nil
  
      @datefmt = "%b %d %H:%M:%S"
  
      return if dest == nil
  
      adest = dest.split(",")
      adest.each do |d|
        d.strip!
        puts "Setting dest=#{d}" if @debug
        case d
        when 'console'
          @console = MsgObject.new("console", $stdout, nil, true)
        else
          puts "Unknown log destination \"#{d}\" in #{me}"
        end
      end
      # default log level
    end
  private
    def msgMessage(msg, lvl)
      # console
      # syslog
      # private log
      # notification
      puts "Unknown message level=%{lvl}" if not $LOGLEVELS.has_key?(lvl)
      return if $LOGLEVELS[lvl].to_i > @loglevel
      msg.each_line do |line|
        @console << line if @console
        @notify << line if @notify
        # only print blank lines to console
        next if line.length == 1
        @privlog << line if @privlog
      end
    end
  public
    def set_client(client="localhost")
      @console.client = client if @console
      @privlog.client = client if @privlog
      @syslog.client = client if @syslog
      @notify.client = client if @notify
    end
  
    # Jan 17 09:08:33 host 
    # %b %d %H:%M:%S hostname
    def privlog(name, dir, perm=0644)
      @logname = name
      @logdir = dir
  
      if not File.exist?(dir)
        begin
          FileUtils.mkdir(dir)
        rescue Errno::EACCES
          die "permission denied creating log dir #{dir}"
        rescue
          die "creating log dir #{dir}"
        end
      end
      if not File.stat(dir).directory?
        die "#{dir} is not a directory"
      end
  
      log = File.join(@logdir, @logname)
      privlog = File.new(log, File::CREAT|File::APPEND|File::RDWR, perm)
      @privlog = MsgObject.new("privlog", privlog, @datefmt, false) if privlog
    end
  
    def privlog_path
      @privlog ? @privlog.io.path : ""
    end
  
    # email notify
    # MsgObject.notify("me@somewhere.com", "My Name", "root@localhost", "Rubac backup")
    def notify(to_addr, from_addr="rubac@localhost", server="localhost")
      #@notify = MsgObject.new("notify", nil, @datefmt, false) if @notify == nil
      @notify = MsgObject.new("notify", nil, nil, false) if @notify == nil
  
      @email = Email.new(server)
      @email.to(to_addr)
      @email.from(from_addr)
    end
  
    def send_notify(subject="Rubac notification")
      return if @notify == nil
      #$msg.puts "!!!!!\nsubject=#{subject}\nbuffer=#{@notify.io}\n!!!!!"
      return if @notify.io.class != String
      return if @notify.io.length == 0
      @email.send(subject, @notify.io)
      # TODO if successful clear buffer
      @notify.empty 
    end
  
    def level(lvl)
      if $LOGLEVELS[lvl].has_key?
        @loglevel = $LOGLEVELS[lvl]
      else
        @loglevel = $LOGLEVELS["info"]
        err "Unknown log level"
      end
    end
  
    def info(msg)
      msgMessage(msg, "info")
    end
  
    def warn(msg)
      msgMessage("Warning: " + msg, "warn")
    end
  
    def err(msg)
      msgMessage("Error: " + msg, "err")
    end
  
    def debug(msg)
      msgMessage("Debug: " + msg, "debug")
    end
  
    def alert(msg)
      msgMessage("Alert: " + msg, "alert")
    end
  
    def die(msg, e=1)
      err(msg)
      exit e
    end
  
    def printf(fmt, *args)
      #$stdout << sprintf(fmt, *args)
      #@console << msg if @console
      #@notify << msg if @notify
      @console.printf(fmt, *args) if @console
      @notify.printf(fmt, *args) if @notify
    end
  
    def puts(msg)
      #$stdout << msg + "\n"
      @console << msg if @console
      @notify << msg if @notify
    end
  
    def print(msg)
      @console.print(msg) if @console
      @notify.print(msg) if @notify
    end
  
    def log(msg)
      @privlog << msg if @privlog
    end
  end
end
