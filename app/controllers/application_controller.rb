class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  
  protected
  
  def current_admin
    return nil unless session[:admin_id]
    @current_admin ||= AdminUser.active.find_by(id: session[:admin_id])
  end
  helper_method :current_admin
end
