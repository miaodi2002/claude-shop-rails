# Sidekiq Web UI Authentication
require 'sidekiq/web'

# Configure Sidekiq Web authentication
Sidekiq::Web.use ActionDispatch::Cookies
Sidekiq::Web.use ActionDispatch::Session::CookieStore, key: "_claude_shop_session"

# Custom authentication for Sidekiq Web UI
class AdminConstraint
  def self.matches?(request)
    return false unless request.session[:admin_id]
    
    # Find the admin user
    admin = AdminUser.find_by(id: request.session[:admin_id])
    
    # Only allow active admins with admin or super_admin roles
    admin && admin.active? && (admin.role == 'admin' || admin.role == 'super_admin')
  end
end