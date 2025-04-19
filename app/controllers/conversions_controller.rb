class ConversionsController < ApplicationController
  def index
    # Handle showing conversion status on homepage if conversion_id is present
    if params[:conversion_id]
      @conversion = Conversion.find_by(id: params[:conversion_id])
    else
      @conversion = nil
    end
  end
  
  def create
    @conversion = Conversion.new(conversion_params)
    
    if @conversion.save
      # Enqueue background job to process the conversion
      ConversionWorker.perform_async(@conversion.id)
      
      respond_to do |format|
        format.html { redirect_to root_path(conversion_id: @conversion.id) }
        format.json { render json: @conversion }
      end
    else
      respond_to do |format|
        format.html { render :index }
        format.json { render json: { errors: @conversion.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def status
    begin
      @conversion = Conversion.find(params[:id])
      
      # Force reload to ensure we have the latest data
      @conversion.reload
      
      response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = '0'
      
      render partial: 'conversion_status', locals: { conversion: @conversion }, layout: false
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error("Status error: Conversion #{params[:id]} not found - #{e.message}")
      render plain: "Conversion not found", status: 404
    rescue StandardError => e
      Rails.logger.error("Status error: #{e.message}\n#{e.backtrace.join("\n")}")
      render plain: "Error loading status: #{e.message}", status: 500
    end
  end

  def show
    @conversion = Conversion.find(params[:id])
    # Always reload from the database to get the latest status
    @conversion.reload
    
    # Log status for debugging
    Rails.logger.info("Conversion #{@conversion.id} JSON response: " +
                     "status=#{@conversion.status}, " +
                     "title=#{@conversion.title}, " +
                     "error=#{@conversion.error_message}, " +
                     "s3_url=#{@conversion.s3_url}")
    
    respond_to do |format|
      format.html
      format.json { render json: {
        id: @conversion.id,
        status: @conversion.status,
        title: @conversion.title,
        duration: @conversion.formatted_duration,
        error_message: @conversion.error_message,
        s3_url: @conversion.s3_url, # Add this to see if s3_url is properly set
        # Add a timestamp to force cache invalidation
        timestamp: Time.now.to_i
      }}
    end
  end
  
  def download
    @conversion = Conversion.find(params[:id])
    
    if @conversion.status == 'completed'
      if @conversion.s3_url.present?
        # Generate a presigned URL and redirect to it
        presigned_url = @conversion.presigned_download_url
        
        if presigned_url
          # Log the successful URL generation (don't log the full URL for security)
          Rails.logger.info("Generated presigned URL for conversion ##{@conversion.id}")
          redirect_to presigned_url, allow_other_host: true
        else
          Rails.logger.error("Failed to generate presigned URL for conversion ##{@conversion.id}, S3 URL: #{@conversion.s3_url}")
          redirect_to conversion_path(@conversion), alert: 'Error generating download link. Please contact support.'
        end
      elsif @conversion.file_path.present? && File.exist?(@conversion.file_path)
        # Fallback to local file download if S3 URL is not available
        Rails.logger.info("Serving local file for conversion ##{@conversion.id}: #{@conversion.file_path}")
        send_file @conversion.file_path, type: 'audio/mpeg', filename: @conversion.filename
      else
        Rails.logger.warn("File not found for conversion ##{@conversion.id}. S3 URL: #{@conversion.s3_url}, File path: #{@conversion.file_path}")
        redirect_to conversion_path(@conversion), alert: 'File is not ready for download yet.'
      end
    else
      redirect_to conversion_path(@conversion), alert: 'Conversion is not completed yet.'
    end
  end
  
  private
  
  def conversion_params
    params.require(:conversion).permit(:url, :quality)
  end
end