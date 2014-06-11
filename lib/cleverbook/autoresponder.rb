require 'xmpp4r_facebook'
require 'cleverbot'

module Cleverbook
  class Autoresponder
    include Methadone::Main
    include Methadone::CLILogging
    include Jabber

    def initialize(facebook_profile, app_id, access_token, app_secret)
      @facebook_profile = facebook_profile
      @user_id = @facebook_profile["id"]
      @app_id = app_id
      @access_token = access_token
      @app_secret = app_secret
      @client = nil
      # Add last message params for continuous sessions with cleverbot when mixed @params = params
      # Build jabber_id here and factor out @user_id
    end

    attr_reader :facebook_profile, :user_id, :app_id, :access_token, :app_secret
    attr_accessor :client #, :params

    def build_client
      info "Builing Jabber client"
      debug "USERID: #{@user_id}"
      debug "APPID: #{@app_id}"
      debug "APP SECRET: #{@app_secret}"
      debug "ACCESS TOKEN: #{@access_token}"
      jabber_id = "#{@user_id}@chat.facebook.com"
      debug "JABBERID: #{jabber_id}"
      begin
        @client = Jabber::Client.new Jabber::JID.new(jabber_id)
        @client.connect
        @client.auth_sasl(Jabber::SASL::XFacebookPlatform.new(@client, @app_id, @access_token, @app_secret), nil)
        @client
      rescue => e
        warn "Failed to build Jabber client"
        debug "USERID: #{@user_id}"
        debug "APPID: #{@app_id}"
        debug "APP SECRET: #{@app_secret}"
        debug "ACCESS TOKEN: #{@access_token}"
        debug "JABBERID: #{jabber_id}"
        error "#{e}"
      end
    end

    def run_bot_only_response_thread
      # Get all responses from cleverbot
      jabber_id = "#{@user_id}@chat.facebook.com"
      Jabber::debug = true
      convo = {}
      @client.send(Presence.new)
      puts "Connected ! send messages to #{jabber_id}."
      mainthread = Thread.current
      @client.add_message_callback do |m|
        if m.type != :error
          if m.body == 'exit'
            m2 = Message.new(m.from, "Exiting ...")
            m2.type = m.type
            @client.send(m2)
            mainthread.wakeup
          end
          m2, convo[m.from] = build_message_bot(@user_id, m.from, m.body, convo[m.from])
          m2.type = m.type
          @client.send(m2) unless m.body.nil?
        end
      end
      Thread.stop
      @client.close
    end

    def run_script_bot_mix_response_thread
      # Get responses from a YAML config file. If suitable response isn't found we get one from cleverbot
      jabber_id = "#{@user_id}@chat.facebook.com"
      Jabber::debug = true
      convo = {}
      @client.send(Presence.new)
      puts "Connected ! send messages to #{jabber_id}."
      mainthread = Thread.current
      @client.add_message_callback do |m|
        if m.type != :error
          if m.body == 'exit'
            m2 = Message.new(m.from, "Exiting ...")
            m2.type = m.type
            @client.send(m2)
            mainthread.wakeup
          end          
          m2 = build_message_script(@user_id, m.from, m.body)
          m2.type = m.type
          @client.send(m2) unless m.body.nil?
        end
      end
      Thread.stop
      @client.close
    end

    protected

    def send_message(message)
      # Send standard xmpp message. Not currently used. Consider factoring out
      info "Sending xmpp message"
      debug "MESSAGE: #{message}"
      begin
        @client.send message
      rescue => e
        warn "Failed to send xmpp message"
        debug "CLIENT: #{@client.to_s}"
        debug "MESSAGE: #{message}"
        error "#{e}"
      end
    end

    def close_client
      # Close client when finished. Not currently used. Save for time limits maybe
      @client.close
    end

    def build_message_bot(to, incoming_message, params = {})
      # Calls method to get response from clever bot and formats it to be sent
      # Params are returned to be sent back to cleverbot for continuous dialogue
      id = "#{@user_id}@chat.facebook.com"
      params = get_response_from_cleverbot(incoming_message, params)
      body = params["message"]
      subject = "Droid Message ID: #{((0...12).map { (65 + rand(26)).chr }.join).downcase}"
      message = Jabber::Message.new to, body
      message.subject = subject
      return message, params
    end

    def build_message_script(to, incoming_message)
      # Calls method to use ChatBot AI loaded from YAML file to try to find suitable response
      # In the ChatBot if no suitable response is found it gets one from Cleverbot.
      # Response is then formatted to be sent
      id = "#{@user_id}@chat.facebook.com"
      body = get_response_from_script(incoming_message)
      subject = "Droid Message ID: #{((0...12).map { (65 + rand(26)).chr }.join).downcase}"
      message = Jabber::Message.new to, body
      message.subject = subject
      return message
    end

    def get_response_from_script(incoming_message)
      # Does the work of getting a response from our ChatBot if none is found we get it from Cleverbot
      # Our ChatBot returns a String while Cleverbot returns a Hash of continuous dialogue
      cb = Cleverbook::ChatBot.new("default.yml", "quotes")
      response = cb.get_response incoming_message
      response.is_a?(String) ? response : response.text
    end

    def get_response_from_cleverbot(incoming_message, params = {})
      # Does the work of getting a response from Cleverbot. Response is a Hash
      # @params["message"] is the last message recieved from CB
      @params = Cleverbot::Client.write my_message, params
    end

    def replace_words_in_response(response, options = {})
      # Not used yet. Work on a better implementation
      # TODO: Load replacement words into options hash from a yml config file     
      options["cleverbot"] = @facebook_profile["first_name"]
      # Regex replace case-insensitive Hash key with hash value
      options.each { |k, v| response.gsub!(/#{k}/i, v) }
      response
    end
  end
end