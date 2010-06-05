$LOAD_PATH.unshift File.expand_path(File.join(File.dirname(__FILE__), ".."))

require 'rubygems'
require 'sinatra'
require 'soap/rpc/router'
require 'digest/md5'
require 'lib/archive'
require 'lib/eyefi'
require 'builder'

def soap_to_object(body)
  SOAP::Mapping.soap2obj(SOAP::Processor.unmarshal(body).body.root_node)
end

class PatchedSinatraApp < Sinatra::Base
  class << self
    private
    def soap_action(pattern)
      condition {
        env['HTTP_SOAPACTION'].include? pattern
      }
    end
  end
end

##############################################################################

class RyfiApp < PatchedSinatraApp
  
  set :lock, true
  
  @@snonce = Digest::MD5.hexdigest((0...8).map{65.+(rand(25)).chr}.join)
  @@card_auth_handler = nil
  
  class << self
    def handle_photos_with(handler)
      @@photo_handler = handler
    end
    def authorize_cards(handler)
      @@card_auth_handler = handler
    end
  end
  
  before do
    env['CONTENT_TYPE'] ||= ''
    if env['HTTP_USER_AGENT'].include? 'Eye-Fi Card'
      unless env['CONTENT_TYPE'].include? 'multipart/form-data'
        post_body = request.body.read
        params[:soap] = soap_to_object(post_body) if post_body.length > 1
      else
        params[:soap] = soap_to_object(params[:SOAPENVELOPE])
      end
      # find card by mac
      unless @@card_auth_handler.nil?
        params[:card] = self.send(@@card_auth_handler, params[:soap].macaddress)
      else
        params[:card] = EyefiCard.find_by_mac(params[:soap].macaddress)
      end
      response['Server'] = 'Eye-Fi Agent/2.0.4.0 (Windows XP SP2)'
      content_type 'application/xml', :charset => 'utf-8'
    end  
  end
  
  # Handle StartSession
  post '/api/soap/eyefilm/v1', :soap_action => 'urn:StartSession', :agent => /Eye-Fi Card/ do
    
    builder do |xml|
      xml.instruct! :xml, :version => '1.0'
      xml.tag!('SOAP-ENV:Envelope', 'xmlns:SOAP-ENV' => 'http://schemas.xmlsoap.org/soap/envelope/'){
        xml.tag!('SOAP-ENV:Body'){
          xml.tag!('StartSessionResponse', :xmlns => 'http://localhost/api/soap/eyefilm'){
            xml.credential params[:card].credential(params[:soap].cnonce)
            xml.snonce @@snonce
            xml.transfermode '2'
            xml.transfermodetimestamp params[:soap].transfermodetimestamp
            xml.upsyncallowed 'false'
          }
        }
      }
    end
    
  end
  
  # Handle GetPhotoStatus
  post '/api/soap/eyefilm/v1', :soap_action => 'urn:GetPhotoStatus', :agent => /Eye-Fi Card/ do
        
    builder do |xml|
      xml.instruct! :xml
      xml.tag!('SOAP-ENV:Envelope', 'xmlns:SOAP-ENV' => 'http://schemas.xmlsoap.org/soap/envelope/'){
        xml.tag!('SOAP-ENV:Body'){
          xml.tag!('GetPhotoStatusResponse', :xmlns => 'http://localhost/api/soap/eyefilm'){
            xml.fileid '1'
            xml.offset '0'
          }
        }
      }
    end
    
  end
  
  # Handle MarkLastPhotoInRoll
  post '/api/soap/eyefilm/v1', :soap_action => 'urn:MarkLastPhotoInRoll', :agent => /Eye-Fi Card/ do
        
    builder do |xml|
      xml.instruct! :xml
      xml.tag!('SOAP-ENV:Envelope', 'xmlns:SOAP-ENV' => 'http://schemas.xmlsoap.org/soap/envelope/'){
        xml.tag!('SOAP-ENV:Body'){
          xml.tag!('MarkLastPhotoInRollResponse', :xmlns => 'http://localhost/api/soap/eyefilm')
        }
      }
    end
    
  end
  
  # Handle Upload
  post '/api/soap/eyefilm/v1/upload', :agent => /Eye-Fi Card/ do
        
    photo = params[:card].receive_photo(params['FILENAME'][:tempfile], params['INTEGRITYDIGEST'], params[:soap])
    self.send(@@photo_handler, params[:card], photo)
    
    EyefiCard.log.debug "Sending upload response..."
    
    builder do |xml|
      xml.instruct! :xml
      xml.tag!('SOAP-ENV:Envelope', 'xmlns:SOAP-ENV' => 'http://schemas.xmlsoap.org/soap/envelope/'){
        xml.tag!('SOAP-ENV:Body'){
          xml.tag!('UploadPhotoResponse', :xmlns => 'http://localhost/api/soap/eyefilm'){
            xml.success 'true'
          }
        }
      }
    end
    
  end
  
  # For everything else...
  post '/api/soap/eyefilm/v1', :agent => /Eye-Fi Card/ do
    puts "Unhandled SOAP action: #{env['HTTP_SOAPACTION']}"
  end
  
end