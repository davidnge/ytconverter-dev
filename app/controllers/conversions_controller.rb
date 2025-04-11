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
    Rails.logger.info("Conversion #{@conversion.id} status: #{@conversion.status}, error: #{@conversion.error_message}")
    
    respond_to do |format|
      format.html
      format.json { render json: {
        id: @conversion.id,
        status: @conversion.status,
        title: @conversion.title,
        duration: @conversion.formatted_duration,
        error_message: @conversion.error_message,
        # Add a timestamp to force cache invalidation
        timestamp: Time.now.to_i
      }}
    end
  end
  
  def download
    @conversion = Conversion.find(params[:id])
    
    if @conversion.status == 'completed' && File.exist?(@conversion.file_path)
      send_file @conversion.file_path, type: 'audio/mpeg', filename: @conversion.filename
    else
      redirect_to conversion_path(@conversion), alert: 'File is not ready for download yet.'
    end
  end
  
  private
  
  def conversion_params
    params.require(:conversion).permit(:url, :quality)
  end
  
  def conversion_status
    {
      id: @conversion.id,
      status: @conversion.status || 'pending',
      title: @conversion.title,
      duration: @conversion.formatted_duration,
      progress: @conversion.status == 'completed' ? 100 : (@conversion.status == 'processing' ? 60 : 20),
      error_message: @conversion.error_message
    }
  end
end