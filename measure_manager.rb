require 'rubygems'

require "webrick"
require 'json'
require "openstudio"

class MyServlet < WEBrick::HTTPServlet::AbstractServlet
  
  def initialize(server)
    super
    @osms = {}
    @measures = {}
    
    eval(OpenStudio::Ruleset::infoExtractorRubyFunction)
  end
  
  def get_model(osm_path, force_reload)
    result = nil
    if !force_reload
      result = @osms[osm_path]
    end
    
    if !result
      vt = OpenStudio::OSVersion::VersionTranslator.new
      model = vt.loadModel(osm_path)
        
      if !model.empty?
        result = model.get
        @osms[osm_path] = result
      end
    end
    
    return result
  end
  
  def get_measure(measure_path, force_reload)
    result = nil
    if !force_reload
      result = @measures[measure_path]
    end
    
    if !result
      measure = OpenStudio::BCLMeasure.load(measure_path)

      if !measure.empty?
        result = measure.get
        @measures[measure_path] = result
      end
    end
    
    return result
  end
  
  def do_POST (request, response)

    response.status = 200
    response.content_type = 'application/json'
    
    case request.path
    when "/load_osm"
      begin
        data = JSON.parse(request.body, {:symbolize_names=>true})
        osm_path = data[:osm_path]
        model = get_model(osm_path, true)
        result = !model.nil?
        response.body = JSON.generate({:result=>result})
      rescue Exception => e  
        response.body = JSON.generate({:error=>e.message, :backtrace=>e.backtrace.inspect})
      end
      
    when "/create_measure"
      begin
        data = JSON.parse(request.body, {:symbolize_names=>true})
        measure_path = data[:measure_path]
        name = data[:name]
        class_name = data[:class_name]
        taxonomy_tag = data[:taxonomy_tag]
        measure_type = data[:measure_type]
        description = data[:description]
        modeler_description = data[:modeler_description]
        
        OpenStudio::BCLMeasure.new(name, class_name, measure_path, taxonomy_tag, measure_type.to_MeasureType, description, modeler_description)

        response.body = JSON.generate({:result=>true})
      rescue Exception => e  
        response.body = JSON.generate({:error=>e.message, :backtrace=>e.backtrace.inspect})
      end
      
    when "/compute_arguments"
      begin
        data = JSON.parse(request.body, {:symbolize_names=>true})
        measure_path = data[:measure_path]
        osm_path = data[:osm_path]

        measure = get_measure(measure_path, true)
        model = get_model(osm_path, true)
        
        info = infoExtractor(measure, OpenStudio::Model::OptionalModel.new(model), OpenStudio::OptionalWorkspace.new())
   
        result = []
        info.arguments.each do |argument|
          result << argument.to_s
        end
        
        response.body = JSON.generate({:result=>result})
      rescue Exception => e  
        response.body = JSON.generate({:error=>e.message, :backtrace=>e.backtrace.inspect})
      end
      
    else
      response.body = "Error"
    end
  

  end
  
end

server = WEBrick::HTTPServer.new(:Port => 1234)

server.mount "/", MyServlet

trap("INT") {
    server.shutdown
}

server.start