# frozen_string_literal: true

class JwtService
  # JWT secret key from environment or default for development
  SECRET_KEY = ENV.fetch('JWT_SECRET_KEY', 'claude_shop_jwt_secret_key_2024')
  
  # Token expiration times
  ACCESS_TOKEN_EXPIRY = 24.hours.freeze  # 24 hours for access token
  REFRESH_TOKEN_EXPIRY = 7.days.freeze   # 7 days for refresh token
  
  # Algorithm
  ALGORITHM = 'HS256'
  
  class << self
    # Generate access token for admin
    def encode_access_token(admin)
      payload = {
        admin_id: admin.id,
        username: admin.username,
        role: admin.role,
        exp: (Time.current + ACCESS_TOKEN_EXPIRY).to_i,
        iat: Time.current.to_i,
        jti: generate_jti,
        token_type: 'access'
      }
      
      JWT.encode(payload, SECRET_KEY, ALGORITHM)
    end
    
    # Generate refresh token for admin
    def encode_refresh_token(admin)
      payload = {
        admin_id: admin.id,
        exp: (Time.current + REFRESH_TOKEN_EXPIRY).to_i,
        iat: Time.current.to_i,
        jti: generate_jti,
        token_type: 'refresh'
      }
      
      JWT.encode(payload, SECRET_KEY, ALGORITHM)
    end
    
    # Generate both access and refresh tokens
    def generate_tokens(admin)
      {
        access_token: encode_access_token(admin),
        refresh_token: encode_refresh_token(admin),
        expires_in: ACCESS_TOKEN_EXPIRY.to_i,
        token_type: 'Bearer'
      }
    end
    
    # Decode and validate token
    def decode_token(token)
      decoded = JWT.decode(token, SECRET_KEY, true, algorithm: ALGORITHM)
      payload = decoded[0]
      
      # Check if token is expired
      if Time.current.to_i > payload['exp']
        raise JWT::ExpiredSignature, 'Token has expired'
      end
      
      payload
    rescue JWT::DecodeError => e
      Rails.logger.error "JWT decode error: #{e.message}"
      nil
    end
    
    # Validate access token and return admin
    def decode_access_token(token)
      payload = decode_token(token)
      return nil unless payload
      return nil unless payload['token_type'] == 'access'
      
      admin = Admin.find_by(id: payload['admin_id'])
      return nil unless admin&.active?
      
      # Update last activity
      admin.touch(:last_activity_at) if admin.respond_to?(:last_activity_at)
      
      {
        admin: admin,
        payload: payload
      }
    rescue => e
      Rails.logger.error "Access token validation error: #{e.message}"
      nil
    end
    
    # Validate refresh token
    def decode_refresh_token(token)
      payload = decode_token(token)
      return nil unless payload
      return nil unless payload['token_type'] == 'refresh'
      
      admin = Admin.find_by(id: payload['admin_id'])
      return nil unless admin&.active?
      
      {
        admin: admin,
        payload: payload
      }
    rescue => e
      Rails.logger.error "Refresh token validation error: #{e.message}"
      nil
    end
    
    # Refresh access token using refresh token
    def refresh_access_token(refresh_token)
      result = decode_refresh_token(refresh_token)
      return nil unless result
      
      admin = result[:admin]
      
      # Generate new access token
      new_access_token = encode_access_token(admin)
      
      {
        access_token: new_access_token,
        expires_in: ACCESS_TOKEN_EXPIRY.to_i,
        token_type: 'Bearer'
      }
    rescue => e
      Rails.logger.error "Token refresh error: #{e.message}"
      nil
    end
    
    # Extract token from Authorization header
    def extract_token_from_header(authorization_header)
      return nil unless authorization_header
      
      # Expected format: "Bearer <token>"
      token_match = authorization_header.match(/\ABearer (.+)\z/)
      token_match&.[](1)
    end
    
    # Validate token expiry
    def token_expired?(payload)
      return true unless payload
      
      exp_time = payload['exp']
      return true unless exp_time
      
      Time.current.to_i > exp_time
    end
    
    # Get remaining token lifetime
    def token_remaining_time(payload)
      return 0 unless payload
      
      exp_time = payload['exp']
      return 0 unless exp_time
      
      remaining = exp_time - Time.current.to_i
      [remaining, 0].max
    end
    
    # Check if token needs refresh (less than 1 hour remaining)
    def token_needs_refresh?(payload)
      remaining_time = token_remaining_time(payload)
      remaining_time < 1.hour.to_i
    end
    
    # Revoke token (add to blacklist)
    def revoke_token(jti)
      # Store revoked tokens in Redis with expiration
      return unless jti
      
      redis_key = "revoked_token:#{jti}"
      Redis.current.setex(redis_key, REFRESH_TOKEN_EXPIRY.to_i, '1')
      
      true
    rescue => e
      Rails.logger.error "Token revocation error: #{e.message}"
      false
    end
    
    # Check if token is revoked
    def token_revoked?(jti)
      return false unless jti
      
      redis_key = "revoked_token:#{jti}"
      Redis.current.exists?(redis_key)
    rescue => e
      Rails.logger.error "Token revocation check error: #{e.message}"
      false
    end
    
    # Generate JWT ID for token uniqueness
    def generate_jti
      SecureRandom.uuid
    end
    
    # Decode token without verification (for debugging)
    def decode_without_verification(token)
      JWT.decode(token, nil, false)
    rescue => e
      Rails.logger.error "JWT decode without verification error: #{e.message}"
      nil
    end
    
    # Token information for debugging
    def token_info(token)
      payload = decode_without_verification(token)
      return nil unless payload
      
      token_data = payload[0]
      
      {
        admin_id: token_data['admin_id'],
        username: token_data['username'],
        role: token_data['role'],
        token_type: token_data['token_type'],
        issued_at: Time.at(token_data['iat']),
        expires_at: Time.at(token_data['exp']),
        jti: token_data['jti'],
        expired: token_expired?(token_data),
        remaining_time: token_remaining_time(token_data),
        needs_refresh: token_needs_refresh?(token_data)
      }
    end
    
    private
    
    # Validate admin permissions for token generation
    def validate_admin_for_token(admin)
      raise ArgumentError, 'Admin cannot be nil' unless admin
      raise ArgumentError, 'Admin must be active' unless admin.active?
      raise ArgumentError, 'Admin account is locked' if admin.respond_to?(:locked?) && admin.locked?
      
      true
    end
  end
end