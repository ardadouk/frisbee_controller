
require 'omf_common'

def create_server(controller)

  controller.create(:imagezip_server, hrn: 'imagezip server', ip:"10.64.45.104", port: "9000", image_name: "test.ndz") do |reply_msg|
    if reply_msg.success?
      server = reply_msg.resource
      server.on_subscribed do
        info ">>> Connected to newly created imagezip server #{reply_msg[:hrn]}(id: #{reply_msg[:res_id]})"
        server.on_message do |m|
          info "message #{m}"
        end
      end

      OmfCommon.eventloop.after(5) do
        #release
      end
    else
      error ">>> Resource creation failed - #{reply_msg[:reason]}"
    end
  end
end


entity = OmfCommon::Auth::Certificate.create_from_x509(File.read("/home/ardadouk/.omf/urc.pem"),
                                                       File.read("/home/ardadouk/.omf/user_rc_key.pem"))

OmfCommon.init(:development, communication: { url: 'xmpp://beta:1234@localhost' , auth: {}}) do
  OmfCommon.comm.on_connected do |comm|
    OmfCommon::Auth::CertificateStore.instance.register_default_certs("/home/ardadouk/.omf/trusted_roots/")
    OmfCommon::Auth::CertificateStore.instance.register(entity, OmfCommon.comm.local_topic.address)
    OmfCommon::Auth::CertificateStore.instance.register(entity)

    info "Imagezip Server Test script >> Connected to XMPP"

    comm.subscribe('frisbeeController') do |controller|
      unless controller.error?
        # Now calling create_engine method we defined, with newly created garage topic object
        #
        create_server(controller)
      else
        error controller.inspect
      end
    end

    #OmfCommon.eventloop.after(10) { comm.disconnect }
    comm.on_interrupted { comm.disconnect }
  end
end
