require 'omf_rc'
require 'omf_common'

$stdout.sync = true


module OmfRc::ResourceProxy::FrisbeeController
  include OmfRc::ResourceProxyDSL

  register_proxy :frisbeeController
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

  property :multicast_interface #multicast interface, example 10.0.1.200 (-i arguement)
  property :multicast_address   #multicast address, example 224.0.0.1 (-m arguement)
  property :port                #port, example 7000 (-p arguement)
  property :speed               #bandwidth speed in bits/sec, example 50000000 (-W arguement)
  property :image               #image to burn, example /var/lib/omf-images-5.4/baseline.ndz (no arguement)

   hook :after_initial_configured do |server|
    server.property.app_id = server.hrn.nil? ? server.uid : server.hrn

    ExecApp.new(server.property.app_id, server.build_command_line, server.property.map_err_to_out) do |event_type, app_id, msg|
      user.process_event(server, event_type, app_id, msg)
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
      if event_type == 'EXIT'
        #TODO frisbee server exit inform messages
      elsif event_type == 'STDOUT'
        #TODO frisbee server normal messages inform
      end
  end

  # Build the command line, which will be used to add a new user.
  #
  work('build_command_line') do |res|
    cmd_line = "env -i " # Start with a 'clean' environment
    cmd_line += res.property.binary_path + " " # the /usr/sbin/frisbeed
    cmd_line += "-i " +  res.property.multicast_interface + " " # -i for interface
    cmd_line += "-m " +  res.property.multicast_address + " "   # -m for address
    cmd_line += "-p " +  res.property.port + " "                # -p for port
    cmd_line += "-W " +  res.property.speed + " "               # -W for bandwidth
    cmd_line += res.property.image                              # image no arguement
    cmd_line
  end
end

module OmfRc::ResourceProxy::Frisbee #frisbee client
  include OmfRc::ResourceProxyDSL

  require 'omf_common/exec_app'

  register_proxy :frisbee, :create_by => :frisbeeController

  utility :common_tools
  utility :platform_tools

  property :app_id, :default => nil
  property :binary_path, :default => '/usr/sbin/frisbee'
  property :map_err_to_out, :default => false

  property :multicast_interface #multicast interface, example 10.0.1.200 (-i arguement)
  property :multicast_address   #multicast address, example 224.0.0.1 (-m arguement)
  property :port                #port, example 7000 (-p arguement)
  property :hardrive            #hardrive to burn the image, example /dev/sda (nparguement)
  property :node_topic          #the node

   hook :after_initial_configured do |client|
    client.property.app_id = client.hrn.nil? ? client.uid : client.hrn

    #TODO do the folowing
    #1. subscribe to nodes topic.
    #2. create application proxy
    #3. configure it with binary path and properties
    #4. run the application
    #5. on message inform EC
  end
end

entity = OmfCommon::Auth::Certificate.create_from_x509(File.read("/home/ardadouk/.omf/urc.pem"),
                                                       File.read("/home/ardadouk/.omf/user_rc_key.pem"))

OmfCommon.init(:development, communication: { url: 'xmpp://alpha:1234@localhost', auth: {} }) do
  OmfCommon.comm.on_connected do |comm|
    OmfCommon::Auth::CertificateStore.instance.register_default_certs("/home/ardadouk/.omf/trusted_roots/")
    OmfCommon::Auth::CertificateStore.instance.register(entity, OmfCommon.comm.local_topic.address)
    OmfCommon::Auth::CertificateStore.instance.register(entity)

    info "FrisbeeController >> Connected to XMPP server"
    frisbeeContr = OmfRc::ResourceFactory.create(:frisbeeController, { uid: 'frisbeeController', certificate: entity })
    comm.on_interrupted { frisbeeContr.disconnect }
  end
end
