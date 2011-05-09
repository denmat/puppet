require 'puppet/provider/package'
require 'uri'

# Ruby pears support.
Puppet::Type.type(:package).provide :pear, :parent => Puppet::Provider::Package do
  desc "PHP PEAR support.  A channel URL must passed via `source`. That URL is used as the
    channel repository."

  has_feature :versionable

  commands :pearcmd => "pear"

  def self.pearlist(hash)
    command = [command(:pearcmd), "list"]

#    if hash[:local]
#      command << "--local"
#    else
#      command << "--remote"
#    end

    if name = hash[:justme]
      command << name
    end

    begin
      list = execute(command).split("\n").collect do |set|
        if pearhash = pearsplit(set)
          pearhash[:provider] = :pear
          pearhash
        else
          nil
        end
      end.compact
    rescue Puppet::ExecutionFailure => detail
      raise Puppet::Error, "Could not list pears: #{detail}"
    end

    if hash[:justme]
      return list.shift
    else
      return list
    end
  end

  def self.pearsplit(desc)
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
    pearlist(:local => true).collect do |hash|
      new(hash)
    end
  end

  def install(useversion = true)
    command = [command(:pearcmd), "install"]
    command << "-v" << resource[:ensure] if (! resource[:ensure].is_a? Symbol) and useversion
    # Always include dependencies
    command << "--alldeps"

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
        raise Puppet::Error.new("puppet:// URLs are not supported as pear sources")
      else
        # interpret it as a pear repository
        command << "--source" << "#{source}" << resource[:name]
      end
    else
      command << resource[:name]
    end

    output = execute(command)
    # Apparently some stupid pear versions don't exit non-0 on failure
    self.fail "Could not install: #{output.chomp}" if output.include?("ERROR")
  end

  def latest
    # This always gets the latest version available.
    hash = self.class.pearlist(:justme => resource[:name])

    hash[:ensure]
  end

  def query
    self.class.pearlist(:justme => resource[:name], :local => true)
  end

  def uninstall
    pearcmd "uninstall", "-x", "-a", resource[:name]
  end

  def update
    self.install(false)
  end
end

