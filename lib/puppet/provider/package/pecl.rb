require 'puppet/provider/package'
require 'uri'

# PECL PHP support.
Puppet::Type.type(:package).provide :pecl, :parent => Puppet::Provider::Package do
  desc "PHP PECL support.  A channel URL must passed via `source`. That URL is used as the
    channel repository."

  has_feature :versionable

  commands :peclcmd => "pecl"

  def self.pecllist(hash)
    command = [command(:peclcmd), "list"]

    if name = hash[:justme]
      command << name
    end

    begin
      list = execute(command).split("\n").collect do |set|
        if peclhash = peclsplit(set)
          peclhash[:provider] = :pecl
          peclhash
        else
          nil
        end
      end.compact
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not list pecl: #{detail}"
    end

    if hash[:justme]
      return list.shift
    else
      return list
    end
  end

  def self.peclsplit(desc)
    case desc
    when /(^\S+)\s+(((\d\.)+).)/
      name = $1
      version = $2.split(/,\s*/)[0]
      return {
        :name => name,
        :ensure => version
      }
    else
      Puppet.warning "Could not match #{desc}"
      nil
    end
  end

  def self.instances(justme = false)
    pecllist(:local => true).collect do |hash|
      new(hash)
    end
  end

  def install(useversion = true)
    command = [command(:peclcmd), "install"]
    command << "-v" << resource[:ensure] if (! resource[:ensure].is_a? Symbol) and useversion
    # Always include dependencies
    command << "--include-dependencies"

    if source = resource[:source]
      begin
        uri = URI.parse(source)
      rescue => detail
        fail "Invalid source '#{uri}': #{detail}"
      end

      case uri.scheme
      when nil
        # no URI scheme => interpret the source as a local file
        command << source
      when /file/i
        command << uri.path
      when 'puppet'
        # we don't support puppet:// URLs (yet)
        raise Puppet::Error.new("puppet:// URLs are not supported as pecl sources")
      else
        # interpret it as a pecl repository
        command << "--source" << "#{source}" << resource[:name]
      end
    else
      command << resource[:name]
    end

    output = execute(command)
    # Apparently some stupid gem versions don't exit non-0 on failure
    self.fail "Could not install: #{output.chomp}" if output.include?("ERROR")
  end

  def latest
    # This always gets the latest version available.
    hash = self.class.pecllist(:justme => resource[:name])

    hash[:ensure]
  end

  def query
    self.class.pecllist(:justme => resource[:name], :local => true)
  end

  def uninstall
    peclcmd "uninstall", "-x", "-a", resource[:name]
  end

  def update
    self.install(false)
  end
end

