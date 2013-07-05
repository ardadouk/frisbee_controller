require 'time'
require 'omf_rc'
require 'omf_common'
require 'net/telnet'

$stdout.sync = true

@config = YAML.load_file('../etc/configuration.yaml')
@auth = @config[:auth]
@xmpp = @config[:xmpp]

$all_nodes = []
$ports = []
module OmfRc::ResourceProxy::FrisbeeController
  include OmfRc::ResourceProxyDSL
  property :ports, :default => nil

  register_proxy :frisbeeController

  hook :before_ready do |res|
    @config = YAML.load_file('../etc/configuration.yaml')
    @domain = @config[:domain]
    @nodes = @config[:nodes]

    @nodes.each do |node|
      tmp = {node_name: node[0], node_ip: node[1][:ip], node_mac: node[1][:mac], node_cm_ip: node[1][:cm_ip]}
      $all_nodes << tmp
    end
  end

  request :ports do |res|
    p = 7000
    loop do
      if $ports.include?(p)
        p +=1
      else
        $ports << p
        res.property.ports = p
        break
      end
    end
    res.property.ports.to_s
  end
end

module OmfRc::ResourceProxy::Frisbeed #frisbee server
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :frisbeed, :create_by => :frisbeeController

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => '/usr/sbin/frisbeed'
  property :map_err_to_out, :default => false

  property :multicast_interface, :default => "10.0.0.200" #multicast interface, example 10.0.1.200 (-i arguement)
  property :multicast_address, :default => "224.0.0.1"    #multicast address, example 224.0.0.1 (-m arguement)
  property :port                                          #port, example 7000 (-p arguement)
  property :speed, :default => 50000000                   #bandwidth speed in bits/sec, example 50000000 (-W arguement)
  property :image                                         #image to burn, example /var/lib/omf-images-5.4/baseline.ndz (no arguement)

   hook :after_initial_configured do |server|
    server.property.app_id = server.hrn.nil? ? server.uid : server.hrn

    ExecApp.new(server.property.app_id, server.build_command_line, server.property.map_err_to_out) do |event_type, app_id, msg|
      server.process_event(server, event_type, app_id, msg)
    end
  end

  # This method processes an event coming from the application instance, which
  # was started by this Resource Proxy (RP). It is a callback, which is usually
  # called by the ExecApp class in OMF
  #
  # @param [AbstractResource] res this RP
  # @param [String] event_type the type of event from the app instance
  #                 (STARTED, DONE.OK, DONE.ERROR, STDOUT, STDERR)
  # @param [String] app_id the id of the app instance
  # @param [String] msg the message carried by the event
  #
  def process_event(res, event_type, app_id, msg)
      logger.info "Frisbeed: App Event from '#{app_id}' - #{event_type}: '#{msg}'"
      if event_type == 'EXIT' #maybe i should inform you for every event_type.
        res.inform(:status, {
          status_type: 'FRISBEED',
          event: event_type.to_s.upcase,
          app: app_id,
          exit_code: msg,
          msg: msg
        }, :ALL)
      elsif event_type == 'STDOUT'
        res.inform(:status, {
          status_type: 'FRISBEED',
          event: event_type.to_s.upcase,
          app: app_id,
          exit_code: msg,
          msg: msg
        }, :ALL)
      end
  end

  # Build the command line, which will be used to add a new user.
  #
  work('build_command_line') do |res|
    cmd_line = "env -i " # Start with a 'clean' environment
    cmd_line += res.property.binary_path + " " # the /usr/sbin/frisbeed
    cmd_line += "-i " +  res.property.multicast_interface + " " # -i for interface
    cmd_line += "-m " +  res.property.multicast_address + " "   # -m for address
    cmd_line += "-p " + res.property.port.to_s  + " "           # -p for port
    cmd_line += "-W " + res.property.speed.to_s + " "           # -W for bandwidth
    cmd_line += res.property.image                              # image no arguement
    cmd_line
  end
end

#this one is using telnet to start frisbee on node
module OmfRc::ResourceProxy::Frisbee #frisbee client
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :frisbee, :create_by => :frisbeeController

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => '/usr/sbin/frisbee'
  property :map_err_to_out, :default => false

  property :multicast_interface                           #multicast interface, example 10.0.1.200 (-i arguement)
  property :multicast_address, :default => "224.0.0.1"    #multicast address, example 224.0.0.1 (-m arguement)
  property :port                                          #port, example 7000 (-p arguement)
  property :hardrive, :default => "/dev/sda"              #hardrive to burn the image, example /dev/sda (nparguement)
  property :node_topic                                    #the node

   hook :after_initial_configured do |client|
    node = nil
    $all_nodes.each do |n|
      if n[:node_name] == client.property.node_topic.to_sym
        node = n
      end
    end
    puts "Node : #{node}"
    if node.nil?
      puts "error: Node nill"
      client.inform(:status, {
        event_type: "EXIT",
        exit_code: "-1",
        msg: "Wrong node name."
      }, :ALL)
      client.release
      return
    end

    client.property.multicast_interface = node[:node_ip]
    client.property.app_id = client.hrn.nil? ? client.uid : client.hrn

    command = "#{client.property.binary_path} -i #{client.property.multicast_interface} -m #{client.property.multicast_address} "
    command += "-p #{client.property.port} #{client.property.hardrive}"
    puts "########### running command is #{command}"

    host = Net::Telnet.new("Host" => client.property.multicast_interface.to_s, "Timeout" => 60, "Prompt" => /[\w().-]*[\$#>:.]\s?(?:\(enable\))?\s*$/)
    host.cmd(command.to_s) do |c|
      if c !=  "\n" && (c[0,8] == "Progress" || c[0,5] == "Wrote")
        client.inform(:status, {
          status_type: 'FRISBEE',
          event: "STDOUT",
          app: client.property.app_id,
          node: client.property.node_topic,
          msg: "#{c.to_s}"
        }, :ALL)
      end
    end

    client.inform(:status, {
      status_type: 'FRISBEE',
      event: "EXIT",
      app: client.property.app_id,
      node: client.property.node_topic,
      msg: 'frisbee client completed.'
    }, :ALL)
    host.close
  end
end

#this is the using the omf_rc :application resource controller
# module OmfRc::ResourceProxy::Frisbee #frisbee client
#   include OmfRc::ResourceProxyDSL
#
#   require 'omf_common/exec_app'
#
#   register_proxy :frisbee, :create_by => :frisbeeController
#
#   utility :common_tools
#   utility :platform_tools
#
#   property :app_id, :default => nil
#   property :binary_path, :default => '/usr/sbin/frisbee'
#   property :map_err_to_out, :default => false
#
#   property :multicast_interface, :default => 10.0.0.200 #multicast interface, example 10.0.1.200 (-i arguement)
#   property :multicast_address, :default => 224.0.0.1    #multicast address, example 224.0.0.1 (-m arguement)
#   property :port                                        #port, example 7000 (-p arguement)
#   property :hardrive, :default => "/dev/sda"            #hardrive to burn the image, example /dev/sda (nparguement)
#   property :node_topic                                  #the node
#
#    hook :after_initial_configured do |client|
#     client.property.app_id = client.hrn.nil? ? client.uid : client.hrn
#
#     OmfCommon.comm.subscribe(client.property.node_topic) do |node_rc|
#       unless node_rc.error?
#         node_rc.create(:application, hrn: client.property.node_topic) do |reply_msg|
#           if reply_msg.success?
#             app = reply_msg.resource
#             app.on_subscribed do
#               app.on_message do |m|
#                 if m.read_property("status_type") == 'APP_EVENT'
#                   client.inform(:status, {
#                     status_type: 'APP_EVENT',
#                     event: m.read_property("event"),
#                     app: m.read_property("app"),
#                     exit_code: m.read_property("exit_code"),
#                     msg: m.read_property("msg")
#                   }, :ALL)
#                 end
#               end
#               app.configure(binary_path: client.property.binary_path)
#               sleep 1
#               params = {
#                 :multicast_interface => {:type => 'String', :cmd => '-i', :mandatory => true, :order => 1, :value => client.property.multicast_interface},
#                 :multicast_address => {:type => 'String', :cmd => '-m', :mandatory => true, :order => 2, :value => client.property.multicast_address},
#                 :port => {:type => 'Integer', :cmd => '-p', :mandatory => true, :order => 3, :value => client.property.port},
#                 :hardrive => {:type => 'String', :cmd => '', :mandatory => true, :order => 4, :value => client.property.hardrive}
#               }
#               app.configure(parameters: params)
#               sleep 1
#               app.configure(state: :running)
#             end
#           else
#             error ">>> App Resource failed to create - #{reply_msg[:reason]}"
#           end
#         end
#       end
#     end
#   end
# end

module OmfRc::ResourceProxy::ImagezipServer #Imagezip server
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :imagezip_server, :create_by => :frisbeeController

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => '/bin/nc'
  property :map_err_to_out, :default => false

  property :ip, :default => "10.0.0.200"
  property :port, :default => "9000"
  property :image_name, :default => "image.ndz"

  hook :after_initial_configured do |server|
    server.property.app_id = server.hrn.nil? ? server.uid : server.hrn

    ExecApp.new(server.property.app_id, server.build_command_line, server.property.map_err_to_out) do |event_type, app_id, msg|
      server.process_event(server, event_type, app_id, msg)
    end
  end

  def process_event(res, event_type, app_id, msg)
      logger.info "Frisbeed: App Event from '#{app_id}' - #{event_type}: '#{msg}'"
      if event_type == 'EXIT' #maybe i should inform you for every event_type, we'll see.
        res.inform(:status, {
          status_type: 'IMAGEZIP',
          event: event_type.to_s.upcase,
          app: app_id,
          exit_code: msg,
          msg: msg
        }, :ALL)
      elsif event_type == 'STDOUT'
        res.inform(:status, {
          status_type: 'IMAGEZIP',
          event: event_type.to_s.upcase,
          app: app_id,
          exit_code: msg,
          msg: msg
        }, :ALL)
      end
  end

  work('build_command_line') do |res|
    cmd_line = "env -i " # Start with a 'clean' environment
    cmd_line += res.property.binary_path + " "
    cmd_line += "-d -l  " +  res.property.ip + " " + res.property.port.to_s + " > " +  res.property.image_name
    cmd_line
  end
end

module OmfRc::ResourceProxy::ImagezipClient #Imagezip client
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :imagezip_client, :create_by => :frisbeeController

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => '/usr/bin/imagezip'
  property :map_err_to_out, :default => false

  property :ip, :default => "10.0.0.200"
  property :port
  property :hardrive, :default => "/dev/sda"
  property :node_topic

   hook :after_initial_configured do |client|
    node = nil
    $all_nodes.each do |n|
      if n[:node_name] == client.property.node_topic.to_sym
        node = n
      end
    end
    puts "Node : #{node}"
    if node.nil?
      puts "error: Node nill"
      client.inform(:status, {
        event_type: "EXIT",
        exit_code: "-1",
        msg: "Wrong node name."
      }, :ALL)
      client.release
      return
    end

    client.property.app_id = client.hrn.nil? ? client.uid : client.hrn

    command = "#{client.property.binary_path} -z1 #{client.property.hardrive} - | nc -q 0 #{client.property.ip} #{client.property.port}"
    puts "########### running command is #{command}"

    host = Net::Telnet.new("Host" => node[:node_ip], "Timeout" => 60, "Prompt" => /[\w().-]*[\$#>:.]\s?(?:\(enable\))?\s*$/)
    host.cmd(command.to_s) do |c|
      if c !=  "\n" #&& (c[0,8] == "Progress" || c[0,5] == "Wrote")
        client.inform(:status, {
          status_type: 'IMAGEZIP',
          event: "STDOUT",
          app: client.property.app_id,
          node: client.property.node_topic,
          msg: "#{c.to_s}"
        }, :ALL)
      end
    end

    client.inform(:status, {
      status_type: 'IMAGEZIP',
      event: "EXIT",
      app: client.property.app_id,
      node: client.property.node_topic,
      msg: 'imagezip client completed.'
    }, :ALL)
    host.close
  end
end

#this is the imagezip client that uses the application resource controller
# module OmfRc::ResourceProxy::ImagezipClient #Imagezip client
#   include OmfRc::ResourceProxyDSL
#
#   require 'omf_common/exec_app'
#
#   register_proxy :imagezip_client, :create_by => :frisbeeController
#
#   utility :common_tools
#   utility :platform_tools
#
#   property :app_id, :default => nil
#   property :binary_path, :default => '/usr/sbin/imagezip'
#   property :map_err_to_out, :default => false
#
#   property :ip
#   property :port
#   property :hardrive
#   property :node_topic
#
#    hook :after_initial_configured do |client|
#     client.property.app_id = client.hrn.nil? ? client.uid : client.hrn
#
#     OmfCommon.comm.subscribe(client.property.node_topic) do |node_rc|
#       unless node_rc.error?
#         node_rc.create(:application, hrn: client.property.node_topic) do |reply_msg|
#           if reply_msg.success?
#             app = reply_msg.resource
#             app.on_subscribed do
#               app.on_message do |m|
#                 if m.read_property("status_type") == 'APP_EVENT'
#                   client.inform(:status, {
#                     status_type: 'APP_EVENT',
#                     event: m.read_property("event"),
#                     app: m.read_property("app"),
#                     exit_code: m.read_property("exit_code"),
#                     msg: m.read_property("msg")
#                   }, :ALL)
#                 end
#               end
#               app.configure(binary_path: client.property.binary_path)
#               sleep 1
#               params = {
#                 :hardrive => {:type => 'String', :cmd => '-z1', :mandatory => true, :order => 1, :value => client.property.hardrive},
#                 :ip => {:type => 'String', :cmd => '- | nc -q 0', :mandatory => true, :order => 2, :value => client.property.ip},
#                 :port => {:type => 'Integer', :cmd => '', :mandatory => true, :order => 3, :value => client.property.port}
#               }
#               app.configure(parameters: params)
#               sleep 1
#               app.configure(state: :running)
#             end
#           else
#             error ">>> App Resource failed to create - #{reply_msg[:reason]}"
#           end
#         end
#       end
#     end
#   end
# end

entity_cert = File.expand_path(@auth[:entity_cert])
entity_key = File.expand_path(@auth[:entity_key])
entity = OmfCommon::Auth::Certificate.create_from_x509(File.read(entity_cert), File.read(entity_key))

trusted_roots = File.expand_path(@auth[:root_cert_dir])

OmfCommon.init(:development, communication: { url: "xmpp://#{@xmpp[:username]}:#{@xmpp[:password]}@#{@xmpp[:server]}", auth: {} }) do
  OmfCommon.comm.on_connected do |comm|
    OmfCommon::Auth::CertificateStore.instance.register_default_certs(trusted_roots)
    OmfCommon::Auth::CertificateStore.instance.register(entity, OmfCommon.comm.local_topic.address)
    OmfCommon::Auth::CertificateStore.instance.register(entity)

    info "FrisbeeController >> Connected to XMPP server"
    frisbeeContr = OmfRc::ResourceFactory.create(:frisbeeController, { uid: 'frisbeeController', certificate: entity })
    comm.on_interrupted { frisbeeContr.disconnect }
  end
end
