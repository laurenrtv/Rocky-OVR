#***** BEGIN LICENSE BLOCK *****
#
#Version: RTV Public License 1.0
#
#The contents of this file are subject to the RTV Public License Version 1.0 (the
#"License"); you may not use this file except in compliance with the License. You
#may obtain a copy of the License at: http://www.osdv.org/license12b/
#
#Software distributed under the License is distributed on an "AS IS" basis,
#WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the
#specific language governing rights and limitations under the License.
#
#The Original Code is the Online Voter Registration Assistant and Partner Portal.
#
#The Initial Developer of the Original Code is Rock The Vote. Portions created by
#RockTheVote are Copyright (C) RockTheVote. All Rights Reserved. The Original
#Code contains portions Copyright [2008] Open Source Digital Voting Foundation,
#and such portions are licensed to you under this license by Rock the Vote under
#permission of Open Source Digital Voting Foundation.  All Rights Reserved.
#
#Contributor(s): Open Source Digital Voting Foundation, RockTheVote,
#                Pivotal Labs, Oregon State University Open Source Lab.
#
#***** END LICENSE BLOCK *****
class PartnerBase < ApplicationController
  layout "partners"
  
  helper_method :current_partner_session, :current_partner
  before_action :init_nav_class


  def current_partner
    return @current_partner if defined?(@current_partner)
    @current_partner = current_partner_session && current_partner_session.record
  end

  protected

  def current_partner_session
    return @current_partner_session if defined?(@current_partner_session)
    @current_partner_session = PartnerSession.find
  end

  def require_partner
    unless current_partner
      store_location
      flash[:warning] = "You must be logged in to access this page"
      redirect_to login_url
      return false
    end
  end

  def force_logout
    current_partner_session.destroy if current_partner
    remove_instance_variable :@current_partner_session if defined?(@current_partner_session)
    remove_instance_variable :@current_partner if defined?(@current_partner)
    reset_session
  end

  def store_location
    session[:return_to] = request.fullpath
  end

  def redirect_back_or_default(default)
    rt = session[:return_to]
    session[:return_to] = nil
    redirect_to(rt || default)
  end

  def init_nav_class
    @nav_class = Hash.new
  end
  
end
