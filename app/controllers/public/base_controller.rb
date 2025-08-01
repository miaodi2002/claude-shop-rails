# frozen_string_literal: true

module Public
  class BaseController < ApplicationController
    # 布局文件
    layout 'public'
    
    # SEO和性能优化
    before_action :set_cache_headers
    before_action :set_meta_tags
    
    private
    
    def set_cache_headers
      # 公开页面可以被缓存
      expires_in 10.minutes, public: true
    end
    
    def set_meta_tags
      @meta_title = 'Claude Shop - AWS Bedrock配额账号'
      @meta_description = '专业的AWS Bedrock Claude模型配额账号交易平台，提供Claude 3.5、Claude 3.7、Claude 4等模型的高配额账号'
      @meta_keywords = 'AWS Bedrock, Claude, 配额账号, Claude 3.5 Sonnet, Claude 3.7 Sonnet, Claude 4 Sonnet'
    end
  end
end