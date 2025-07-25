# frozen_string_literal: true

class JwtAuthenticationMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    request = Rack::Request.new(env)
    
    # Skip authentication for specific paths
    if skip_authentication?(request.path_info)
      return @app.call(env)
    end
    
    # Extract and validate token
    token = extract_token_from_header(request.get_header('HTTP_AUTHORIZATION'))
    
    if token
      result = validate_token(token)
      if result
        # Add admin info to environment for controllers
        env['current_admin'] = result[:admin]
        env['current_token_payload'] = result[:payload]
        
        # Log token usage for monitoring
        log_token_usage(result[:admin], request)
      else
        # Invalid token - return unauthorized
        return unauthorized_response('Token无效或已过期')
      end
    else
      # No token provided for protected route
      return unauthorized_response('请提供访问令牌')
    end
    
    @app.call(env)
  rescue => e
    Rails.logger.error "JWT Middleware Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    server_error_response
  end
  
  private
  
  def skip_authentication?(path)
    # Paths that don't require authentication
    skip_paths = [
      '/api/v1/auth/login',
      '/api/v1/auth/refresh',
      '/health',
      '/api/v1/status',
      '/favicon.ico'
    ]
    
    # Skip paths starting with certain patterns
    skip_patterns = [
      '/assets/',
      '/public/',
      '/rails/',
      '/cable'
    ]
    
    # Check exact matches
    return true if skip_paths.include?(path)
    
    # Check pattern matches
    skip_patterns.any? { |pattern| path.start_with?(pattern) }
  end
  
  def extract_token_from_header(authorization_header)
    JwtService.extract_token_from_header(authorization_header)
  end
  
  def validate_token(token)
    result = JwtService.decode_access_token(token)
    return nil unless result
    
    admin = result[:admin]
    payload = result[:payload]
    
    # Additional security checks
    return nil unless admin&.active?
    return nil if admin.locked?
    
    # Check if token is revoked
    jti = payload['jti']
    return nil if jti && JwtService.token_revoked?(jti)
    
    # Update last activity time
    update_last_activity(admin)
    
    result
  rescue => e
    Rails.logger.error "Token validation error: #{e.message}"
    nil
  end
  
  def update_last_activity(admin)
    # Update last activity time asynchronously to avoid blocking requests
    admin.update_column(:last_activity_at, Time.current)
  rescue => e
    Rails.logger.error "Failed to update last activity: #{e.message}"
  end
  
  def log_token_usage(admin, request)
    # Log token usage for security monitoring (optional)
    # This could be sent to a monitoring service or stored in logs
    Rails.logger.info "Token used by admin #{admin.username} from #{request.ip}"
  rescue => e
    Rails.logger.error "Failed to log token usage: #{e.message}"
  end
  
  def unauthorized_response(message = '未授权访问')
    [
      401,
      {
        'Content-Type' => 'application/json',
        'Cache-Control' => 'no-cache, no-store, must-revalidate',
        'Pragma' => 'no-cache',
        'Expires' => '0'
      },
      [
        {
          success: false,
          message: message,
          error_code: 'UNAUTHORIZED',
          timestamp: Time.current.iso8601
        }.to_json
      ]
    ]
  end
  
  def server_error_response
    [
      500,
      { 'Content-Type' => 'application/json' },
      [
        {
          success: false,
          message: '服务器内部错误',
          error_code: 'INTERNAL_SERVER_ERROR',
          timestamp: Time.current.iso8601
        }.to_json
      ]
    ]
  end
end