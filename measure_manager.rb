require 'rubygems'
require 'thread'
require 'webrick'
require 'json'
require 'openstudio'

class MyServlet < WEBrick::HTTPServlet::AbstractServlet

  @@instance = nil
  
  def initialize(server)
    super
    
    @mutex = Mutex.new
    @osms = {} # osm_path => {:checksum, :model}
    @measures = {} # measure_dir => BCLMeasure
    @measure_info = {} # measure_dir => {osm_path => RubyUserScriptInfo}
    
    eval(OpenStudio::Ruleset::infoExtractorRubyFunction)
  end
  
  def self.get_instance(server, *options)
    @@instance = self.new(server, *options) if @@instance.nil?
    return @@instance
  end
  
  def print_message(message)
    #puts message
  end
  
  # returns nil or [OpenStudio::Model::Model, OpenStudio::Workspace], force_reload forces the model to be read from disk
  def get_model(osm_path, force_reload)
    result = nil
    
    # check if model exists on disk
    if !File.exist?(osm_path)
      print_message("Model '#{osm_path}' no longer exists on disk")
      @osms[osm_path] = nil
      force_reload = true
    end    

    if !force_reload
      # load from cache
      temp = @osms[osm_path]
      if temp
        current_checksum = OpenStudio::checksum(OpenStudio::toPath(osm_path))
        last_checksum = temp[:checksum]
        if current_checksum == last_checksum
          result = [temp[:model], temp[:workspace]]
          if result
            print_message("Using cached model '#{osm_path}'")
          end
        end
      end
    end
    
    if !result
      # load from disk
      print_message("Loading model '#{osm_path}'")
      vt = OpenStudio::OSVersion::VersionTranslator.new
      model = vt.loadModel(osm_path)
        
      if model.empty?
        @osms[osm_path] = nil
      else
        model = model.get
        ft = OpenStudio::EnergyPlus::ForwardTranslator.new
        workspace = ft.translateModel(model)
        @osms[osm_path] = {:checksum => current_checksum, :model => model, :workspace => workspace}
        result = [model, workspace]
      end
      
      @measure_info.each_value {|value| value[osm_path] = nil} 
    end
    
    return result
  end
  
  # returns nil or OpenStudio::BCLMeasure from path, force_reload forces the measure.xml to be read from disk
  def get_measure(measure_dir, force_reload)
    
    # check if measure exists on disk
    if !File.exist?(measure_dir) || !File.exist?(File.join(measure_dir, 'measure.xml'))
      print_message("Measure '#{measure_dir}' no longer exists on disk")
      @measures[measure_dir] = nil
      force_reload = true
    end
  
    result = nil
    if !force_reload
      # load from cache
      result = @measures[measure_dir]
      if result
        print_message("Using cached measure '#{measure_dir}'")
      end
    end

    if !result
      # load from disk
      print_message("Loading measure '#{measure_dir}'")
      
      measure = OpenStudio::BCLMeasure.load(measure_dir)
      if measure.empty?
        @measures[measure_dir] = nil
      else
        result = measure.get
        @measures[measure_dir] = result
      end
      
      @measure_info[measure_dir] = {}
    end
    
    if result
      # see if there are updates, want to make sure to perform both checks so do outside of conditional
      file_updates = result.checkForUpdatesFiles # checks if any files have been updated
      xml_updates = result.checkForUpdatesXML # only checks if xml as loaded has been changed since last save
      
      if file_updates || xml_updates
        print_message("Changes detected, updating '#{measure_dir}'")

        # try to load the ruby measure
        info = get_measure_info(measure_dir, result, "", OpenStudio::Model::OptionalModel.new, OpenStudio::OptionalWorkspace.new)
        info.update(result)

        result.save
        @measures[measure_dir] = result
        @measure_info[measure_dir] = {}
      end
    end
    
    return result
  end
  
  # returns OpenStudio::Ruleset::RubyUserScriptInfo 
  def get_measure_info(measure_dir, measure, osm_path, model, workspace)
    
    result = nil
    
    # load from cache
    temp = @measure_info[measure_dir]
    if temp
      result = temp[osm_path]
      if result
        print_message("Using cached measure info for '#{measure_dir}', '#{osm_path}'")
      end
    end
      
    # try to load the ruby measure
    if !result
    
      # DLM: this is where we are executing user's arbitrary Ruby code
      # might need some timeouts or additional protection
      print_message("Loading measure info for '#{measure_dir}', '#{osm_path}'")
      begin
        result = OpenStudio::Ruleset.getInfo(measure, model, workspace)
      rescue Exception => e  
        result = OpenStudio::Ruleset::RubyUserScriptInfo.new(e.message)
      end
      
      @measure_info[measure_dir] = {} if @measure_info[measure_dir].nil?
      @measure_info[measure_dir][osm_path] = result
    end
    
    return result
  end
  
  def get_arguments_from_measure(measure_dir, measure)
    result = []
    
    begin
      # this type was not wrapped with SWIG until OS 1.11.2
      measure.arguments.each do |argument|
        type = argument.type
        
        arg = {}
        arg[:name] = argument.name
        arg[:display_name] = argument.displayName
        arg[:description] = argument.description.to_s
        arg[:type] = argument.type
        arg[:required] = argument.required
        arg[:model_dependent] = argument.modelDependent

        case type
        when 'Boolean'
          if argument.defaultValue.is_initialized
            default_value = argument.defaultValue.get
            arg[:default_value] = (default_value.downcase == "true")
          end
        
        when 'Double'
          arg[:units] = argument.units.get if argument.units.is_initialized
          arg[:default_value] = argument.defaultValue.get.to_f if argument.defaultValue.is_initialized
          arg[:min_value] = argument.minValue.get.to_f if argument.minValue.is_initialized
          arg[:max_value] = argument.maxValue.get.to_f if argument.maxValue.is_initialized
        
        when 'Integer'
          arg[:units] = argument.units.get if argument.units.is_initialized
          arg[:default_value] = argument.defaultValue.get.to_i if argument.defaultValue.is_initialized
        
        when 'String'
          arg[:default_value] = argument.defaultValue.get if argument.defaultValue.is_initialized
        
        when 'Choice'
          arg[:default_value] = argument.defaultValue.get if argument.defaultValue.is_initialized
          arg[:choice_values] = []
          argument.choiceValues.each {|value| arg[:choice_values] << value}
          arg[:choice_display_names] = []
          argument.choiceDisplayNames.each {|value| arg[:choice_display_names] << value}
        
        when 'Path'
          arg[:default_value] = argument.defaultValue.get if argument.defaultValue.is_initialized
        end

        result << arg
      end
    rescue
      info = get_measure_info(measure_dir, measure, "", OpenStudio::Model::OptionalModel.new, OpenStudio::OptionalWorkspace.new)
      return get_arguments_from_measure_info(info)
    end
    
    return result
  end
  
  def get_arguments_from_measure_info(measure_info)
    result = []
    
    measure_info.arguments.each do |argument|
      type = argument.type
      
      arg = {}
      arg[:name] = argument.name
      arg[:display_name] = argument.displayName
      arg[:description] = argument.description.to_s
      arg[:type] = argument.type.valueName
      arg[:required] = argument.required
      arg[:model_dependent] = argument.modelDependent
      
      if type == "Boolean".to_OSArgumentType
        arg[:default_value] = argument.defaultValueAsBool if argument.hasDefaultValue
      
      elsif type == "Double".to_OSArgumentType
        arg[:units] = argument.units.get if argument.units.is_initialized
        arg[:default_value] = argument.defaultValueAsDouble if argument.hasDefaultValue
        
      elsif type == "Quantity".to_OSArgumentType
        arg[:units] = argument.units.get if argument.units.is_initialized
        arg[:default_value] = argument.defaultValueAsQuantity.value if argument.hasDefaultValue
        
      elsif type == "Integer".to_OSArgumentType
        arg[:units] = argument.units.get if argument.units.is_initialized
        arg[:default_value] = argument.defaultValueAsInteger if argument.hasDefaultValue
        
      elsif type == "String".to_OSArgumentType
        arg[:default_value] = argument.defaultValueAsString if argument.hasDefaultValue
      
      elsif type == "Choice".to_OSArgumentType
        arg[:default_value] = argument.defaultValueAsString if argument.hasDefaultValue
          arg[:choice_values] = []
          argument.choiceValues.each {|value| arg[:choice_values] << value}
          arg[:choice_display_names] = []
          argument.choiceValueDisplayNames.each {|value| arg[:choice_display_names] << value}
          
      elsif type == "Path".to_OSArgumentType
        arg[:default_value] = argument.defaultValueAsPath.to_s if argument.hasDefaultValue
        
      end
      
      result << arg
    end
    
    return result
  end
  
  def measure_hash(measure_dir, measure, measure_info = nil)
    result = {}
    result[:measure_dir] = measure_dir
    result[:name] = measure.name
    result[:directory] = measure.directory.to_s
    if measure.error.is_initialized
      result[:error] = measure.error.get
    end
    result[:uid] = measure.uid
    result[:uuid] = measure.uuid.to_s
    result[:version_id] = measure.versionId
    result[:version_uuid] = measure.versionUUID.to_s
    result[:xml_checksum] = measure.xmlChecksum
    result[:name] = measure.name
    result[:display_name] = measure.displayName
    result[:class_name] = measure.className
    result[:description] = measure.description
    result[:modeler_description] = measure.modelerDescription
    result[:tags] = []
    measure.tags.each {|tag| result[:tags] << tag}
    
    result[:outputs] = []
    begin
      # this is an OS 2.0 only method
      measure.outputs.each do |output| 
        out = {}
        out[:name] = output.name
        out[:display_name] = output.displayName
        out[:short_name] = output.shortName.get if output.shortName.is_initialized
        out[:description] = output.description
        out[:type] = output.type
        out[:units] = output.units.get if output.units.is_initialized
        out[:model_dependent] = output.modelDependent
        result[:outputs] << out
      end
    rescue
    end
    
    attributes = []
    measure.attributes.each do |a| 
      value_type = a.valueType
      if value_type == "Boolean".to_AttributeValueType
        attributes << {:name => a.name, :display_name => a.displayName(true).get, :value => a.valueAsBoolean}
      elsif value_type == "Double".to_AttributeValueType
        attributes << {:name => a.name, :display_name => a.displayName(true).get, :value => a.valueAsDouble}
      elsif value_type == "Integer".to_AttributeValueType
        attributes << {:name => a.name, :display_name => a.displayName(true).get, :value => a.valueAsInteger}
      elsif value_type == "Unsigned".to_AttributeValueType
        attributes << {:name => a.name, :display_name => a.displayName(true).get, :value => a.valueAsUnsigned}
      elsif value_type == "String".to_AttributeValueType
        attributes << {:name => a.name, :display_name => a.displayName(true).get, :value => a.valueAsString}
      end
    end
    result[:attributes] = attributes
    
    if measure_info
      result[:arguments] = get_arguments_from_measure_info(measure_info)
    else
      result[:arguments] = get_arguments_from_measure(measure_dir, measure)
    end
    
    return result
  end
  
  def do_GET(request, response)
  
    begin
      @mutex.lock
        
      response.status = 200
      response.content_type = 'application/json'
      
      result = {:status => "running"}
      
      case request.path
      when "/internal_state"
        
        osms = []
        @osms.each_pair do |osm_path, value|  
          if value
            osms << {:osm_path => osm_path, :checksum => value[:checksum]}
          end
        end
        
        measures = []
        @measures.each_pair do |measure_dir, measure|  
          if measure
            measures << measure_hash(measure_dir, measure)
          end
        end
        
        measure_info = []
        @measure_info.each_pair do |measure_dir, value|  
          measure = @measures[measure_dir]
          if measure && value
            value.each_pair do |osm_path, info|
              if info
                temp = measure_hash(measure_dir, measure, info)
                measure_info << {:measure_dir => measure_dir, :osm_path => osm_path, :arguments => temp[:arguments]}
              end
            end
          end
        end
        
        result[:osms] = osms
        result[:measures] = measures
        result[:measure_info] = measure_info
      end
      
      response.body = JSON.generate(result)
    ensure
      @mutex.unlock
    end
  end
  
  def do_POST (request, response)
  
    begin
      @mutex.lock
        
      response.status = 200
      response.content_type = 'application/json'
      
      case request.path
      when "/update_measures"
        begin
          result = []
          
          data = JSON.parse(request.body, {:symbolize_names=>true})
          measures_dir = data[:measures_dir]

          # loop over all directories
          Dir.glob("#{measures_dir}/*/") do |measure_dir|
          
            measure_dir = File.expand_path(measure_dir)
            if File.directory?(measure_dir)
           
              measure = get_measure(measure_dir, false)
              if measure.nil?
                print_message("Directory #{measure_dir} is not a measure")
              else
                result << measure_hash(measure_dir, measure)
              end
            end
          end

          response.body = JSON.generate(result)
        rescue Exception => e  
          response.body = JSON.generate({:error=>e.message, :backtrace=>e.backtrace.inspect})
          #response.status = 400
        end
      
      when "/compute_arguments"
        begin
   
          data = JSON.parse(request.body, {:symbolize_names=>true})
          measure_dir  = data[:measure_dir ]
          osm_path = data[:osm_path]

          measure_dir = File.expand_path(measure_dir)
          measure = get_measure(measure_dir, false)
          if measure.nil?
            raise "Cannot load measure at '#{measure_dir}'"
          end
          
          model = OpenStudio::Model::OptionalModel.new()
          workspace = OpenStudio::OptionalWorkspace.new()
          if osm_path
            osm_path = File.expand_path(osm_path)
            value = get_model(osm_path, false)
            if value.nil?
              raise "Cannot load model at '#{osm_path}'"
            else
              model = value[0]
              workspace = value[1]
            end
          else
            osm_path = ""
          end
          
          info = get_measure_info(measure_dir, measure, osm_path, model, workspace)
     
          result = measure_hash(measure_dir, measure, info)

          response.body = JSON.generate(result)
        rescue Exception => e  
          response.body = JSON.generate({:error=>e.message, :backtrace=>e.backtrace.inspect})
          #response.status = 400
        end
        
      when "/create_measure"
        begin
          data = JSON.parse(request.body, {:symbolize_names=>true})
          measure_dir = data[:measure_dir]
          name = data[:name]
          class_name = data[:class_name]
          taxonomy_tag = data[:taxonomy_tag]
          measure_type = data[:measure_type]
          description = data[:description]
          modeler_description = data[:modeler_description]
          
          measure_dir = File.expand_path(measure_dir)
          OpenStudio::BCLMeasure.new(name, class_name, measure_dir, taxonomy_tag, measure_type.to_MeasureType, description, modeler_description)

          measure = get_measure(measure_dir, true)
          result = measure_hash(measure_dir, measure)
          
          response.body = JSON.generate(result)
        rescue Exception => e  
          response.body = JSON.generate({:error=>e.message, :backtrace=>e.backtrace.inspect})
          #response.status = 400
        end

      when "/duplicate_measure"
        begin
          data = JSON.parse(request.body, {:symbolize_names=>true})
          old_measure_dir = data[:old_measure_dir]
          measure_dir = data[:measure_dir]
          name = data[:name]
          class_name = data[:class_name]
          taxonomy_tag = data[:taxonomy_tag]
          measure_type = data[:measure_type]
          description = data[:description]
          modeler_description = data[:modeler_description]
          
          old_measure_dir = File.expand_path(old_measure_dir)
          old_measure = get_measure(old_measure_dir, true)
          if old_measure.nil?
            raise "Cannot load measure at '#{old_measure_dir}'"
          end
          
          measure_dir = File.expand_path(measure_dir)
          new_measure = old_measure.clone(measure_dir)
          if new_measure.empty?
            raise "Cannot copy measure from '#{old_measure_dir}' to '#{measure_dir}'"
          end
          new_measure = new_measure.get
          
          new_measure.updateMeasureScript(old_measure.measureType, measure_type.to_MeasureType,
                                          old_measure.className, class_name,
                                          name, description, modeler_description)
          
          measure = get_measure(measure_dir, true)
          result = measure_hash(measure_dir, measure)
          
          response.body = JSON.generate(result)
        rescue Exception => e  
          response.body = JSON.generate({:error=>e.message, :backtrace=>e.backtrace.inspect})
          #response.status = 400
        end

      else
        response.body = "Error"
        #response.status = 400
      end
    
    ensure
      @mutex.unlock
    end
  end
  
end

port = ARGV[0]
if port.nil?
  port = 1234
end

server = WEBrick::HTTPServer.new(:Port => port)

server.mount "/", MyServlet

trap("INT") {
    server.shutdown
}

server.start