#
# rsync version must be at least 2.5.6 for --link-dest option
#

module Rubac

  class Config

    attr_reader :config

    #
    # configuration template hash
    #
    def initialize
      @def_config = {
        'globals' => {
          'version' => {
            'major' => '0',
            'minor' => '9',
            'revision' => "$Rev$"[6..-3]
          },
          'opts' => '',
          'includes' => '',
          'excludes' => '',
          'dest' => '',
          'ninc' => '5',
          'logdir' => '',
          'logname' => '',
          'email' => '',
          'smtp' => 'localhost'
        },
        'clients' => {
          'localhost' => {
            'address' => '',
            'includes' => '',
            'excludes' => '',
            'opts' => '',
            'ninc' => '5',
            'compress' => false,
            'incrementals' => { '0' => "" }
          }
        }
      }
      @config = {}
      @config['globals'] = @def_config['globals']
      @config['clients'] = {}
    end
  
    def version
      @config['globals']['version']['major'] + "." +
      @config['globals']['version']['minor'] + " " +
      "(rev #{@config['globals']['version']['revision']})"
    end
  
    # set config file version to match script version, do any version
    # checking here as well for compatibility reasons, if any
    def align_version
      ver = Hash.new
      ver = @def_config['globals']['version']
      # compare ver and @config['globals']['version'] here
      @config['globals']['version'] = ver
    end
  
    def dump
      $msg.info "YAML.dump=" + YAML.dump(@config) + "\n"
    end
  
    def load(file, dir)
      input = File.join(dir, file)
      if not File.exist?(input)
        $msg.warn "configuraton file #{file} not found"
        return false
      end
      @config = File.open(input) { |yf| YAML::load(yf) }
      align_version
      return true
    end
  
    def save_yaml(output)
      File.open(output, "w" ) do |out|
        YAML.dump( @config, out )
      end
    end
  
    def save(file, dir)
      output=File.join(dir, file)
      $msg.info "Saving #{output}"
      if output[/\.yaml$/]
        save_yaml(output)
      else
        $msg.die "unknown file type #{output} in config save"
      end
    end
  
    def add_client(host)
      return if @config['clients'].has_key?(host)
      client = Hash.new
      client["#{host}"] = @def_config['clients']['localhost']
      @config['clients'].merge!(client)
    end
  
    def del_client(host)
      return if not @config['clients'].has_key?(host)
      @config['clients'].delete(host)
    end
  
    def get_global_config
      @config['globals'].to_hash
    end
  
    def del_global_key(key, val, delim=nil)
      return if val == nil or val.length == 0
  
      return if not @config['globals'].has_key?(key)
  
      if not delim
        @config['globals'].delete(key)
        return
      end
  
      items = []
      items = @config['globals']["#{key}"].split(delim)
      return if items.length == 0
  
      vals = val.split(delim)
      vals.each { |k|
        k.strip!
        items.delete(k)
      }
      @config['globals']["#{key}"] = items.join(delim)
    end
  
    def add_global_key(key, val, delim=nil)
      return if val == nil or val.length = 0
  
      if not delim
        items=@config['globals']["#{key}"] = val
        return
      end
      # val can be a comma separated list, should convert to array
      # and compare all values of the with all values in vals below
      vals = val.split(delim)
      vals.each { |k| k.strip! }
      
      items = []
      items=@config['globals']["#{key}"].split(delim) if @config['globals']["#{key}"].length > 0
      # merge, removing duplicates
      items = items | vals
      @config['globals']["#{key}"] = items.join(delim)
    end
  
    def global_update(cmd, key, value, delim=nil)
      return if not value
      value = value.to_s if value.class != String
      case cmd
      when UPDATE_CMD_DEL
        msg = "Deleting"
        del_global_key(key, value, delim)
      when UPDATE_CMD_ADD
        msg = "Adding"
        add_global_key(key, value, delim)
      else
        $msg.err "Unknown command in global_update: #{cmd}"
        return 1
      end
      $msg.info msg + " #{key}=#{value}"
      return 0
    end
  
    def get_global_key_value(key, default = "")
      if not @config['globals'].has_key?("#{key}")
        @config['globals']["#{key}"] = default
      end
      @config['globals']["#{key}"]
    end
  
    def get_global_ninc(ninc)
      get_global_key_value("ninc", @def_config['globals']['ninc'])
    end
  
    def set_global_key_value(key, value)
      return if value == nil
      @config['globals']["#{key}"] = value
    end
  
    def get_global_dest
      @config['globals']['dest'].to_s
    end
  
    def get_client_config(host)
      add_client(host) if not @config['clients'].has_key?(host)
      @config['clients']["#{host}"]
    end
  
    def set_client_key_value(host, key, value)
      get_client_config(host)
      @config['clients']["#{host}"]["#{key}"] = value
    end
  
    # set the value of the incremental string (eg. rubac.2009-12-31_10:10:07.3)
    def set_client_incremental(host, n, name)
      get_client_config(host)
      @config['clients']["#{host}"]['incrementals']["#{n}"] = name
      $msg.debug "set ['clients'][#{host}]['incrementals'][#{n}]=#{name}"
    end
  
    def get_client_incrementals(host, n)
      get_client_config(host)
      if not @config['clients']["#{host}"].has_key?('incrementals')
        $msg.debug "incrementals not found for host=#{host}"
        @config['clients']["#{host}"]['incrementals'] = { "#{n}" => "" }
      end
      if not @config['clients']["#{host}"]['incrementals'].has_key?("#{n}")
        @config['clients']["#{host}"]['incrementals']["#{n}"] = ""
      end
      @config['clients']["#{host}"]['incrementals']["#{n}"].to_s
    end
  
    def del_client_key(host, key, val, delim=nil)
      return if val == nil or val.length == 0
      get_client_config(host)
  
      return if not @config['clients']["#{host}"].has_key?(key)
  
      if not delim
        @config['clients']["#{host}"].delete(key)
        return
      end
  
      items = []
      items = @config['clients']["#{host}"]["#{key}"].split(delim)
      return if items.length == 0
  
      vals = val.split(delim)
      vals.each { |k|
        k.strip!
        items.delete(k)
      }
      @config['clients']["#{host}"]["#{key}"] = items.join(delim)
    end
  
    # append (or set) the specified key for the specified client
    def add_client_key(host, key, val, delim=nil)
      return if val == nil or val.length == 0
  
      get_client_config(host)
  
      if not delim
        @config['clients']["#{host}"]["#{key}"] = val
        return
      end
  
      # val can be a delimite4d separated list, should convert to array
      # and compare all values of the with all values in vals below
      vals = val.split(delim)
      vals.each { |k| k.strip! }
  
      items = []
      if @config['clients']["#{host}"]["#{key}"].length > 0
        items = @config['clients']["#{host}"]["#{key}"].split(delim)
      end
      items = items | vals
      @config['clients']["#{host}"]["#{key}"] = items.join(delim)
    end
  
    # type is add/delete
    #def client_updates(host, type, inc, exc, opts)
    # if type == UPDATE_CMD_DEL
    #   del_client_key(host, "includes", inc)
    #   del_client_key(host, "excludes", exc)
    #   del_client_key(host, "opts", opts, " ")
    # else
    #   add_client_key(host, "includes", inc)
    #   add_client_key(host, "excludes", exc)
    #   add_client_key(host, "opts", opts, " ")
    # end
    #end
  
    # update (add or del) a key/value setting
    def client_update(host, cmd, key, value, delim=nil)
      return if not value
      value = value.to_s if value.class != String
      case cmd
      when UPDATE_CMD_DEL
        msg="Deleting"
        del_client_key(host, key, value, delim)
      when UPDATE_CMD_ADD
        msg="Adding"
        add_client_key(host, key, value, delim)
      else
        $msg.err "Unknown command in client_update: #{cmd}"
      end
      $msg.info msg + " #{key}=#{value}"
    end
  
    def get_clients
      @config['clients'].to_hash
    end
  
    # get the specified key value from globals and clients
    # and return a comma delimited list
    def get_client_key_list(host, key, delim=",")
      get_client_config(host)
  
      entries = []
      entries = get_global_key_value(key).to_s.split(delim)
  
      if @config['clients']["#{host}"].has_key?(key) and @config['clients']["#{host}"]["#{key}"].length > 0
        # eliminate duplicates, if any
        entries = entries | @config['clients']["#{host}"]["#{key}"].split(delim)
      end
      entries.join(delim)
    end
  
    def get_client_includes(host)
      get_client_key_list(host, 'includes')
    end
  
    def get_client_excludes(host)
      get_client_key_list(host, 'excludes')
    end
  
    def get_client_opts(host)
      get_client_key_list(host, 'opts', " ")
    end
  
    def get_client_key_value(host, key)
      get_client_config(host)
      if not @config['clients']["#{host}"].has_key?(key)
        @config['clients']["#{host}"]["#{key}"] = @def_config['clients']['localhost']["#{key}"]
      end
      @config['clients']["#{host}"]["#{key}"]
    end
  
    def get_client_ninc(host)
      # TODO if client ninc is not set use global ninc
      get_client_key_value(host, 'ninc').to_i
    end
  
    def get_client_address(host)
      addr = get_client_key_value(host, 'address')
      addr = host if addr.length == 0
      addr = "localhost" if addr == "127.0.0.1"
      addr
    end
  end
end
