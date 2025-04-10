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
    @conversion = Conversion.find(params[:id])
    render partial: 'conversion_status', locals: { conversion: @conversion }, layout: false
  end

  def show
    @conversion = Conversion.find(params[:id])
    # Force reload from the database to get the latest status
    @conversion.reload if request.format.json?
    
    respond_to do |format|
      format.html
      format.json { render json: {
        id: @conversion.id,
        status: @conversion.status,
        title: @conversion.title,
        duration: @conversion.formatted_duration,
        error_message: @conversion.error_message
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