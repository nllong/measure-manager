require 'rubygems'

require 'webrick'
require 'json'
require 'openstudio'

class MyServlet < WEBrick::HTTPServlet::AbstractServlet
  
  def initialize(server)
    super
    @osms = {}
    @measures = {}
    
    eval(OpenStudio::Ruleset::infoExtractorRubyFunction)
  end
  
  # returns nil or OpenStudio::Model::Model from path, force_reload forces the model to be read from disk
  def get_model(osm_path, force_reload)
    result = nil
    current_checksum = OpenStudio::checksum(OpenStudio::toPath(osm_path))
    
    if !force_reload
      # load from cache
      temp = @osms[osm_path]
      if temp
        last_checksum = temp[:checksum]
        if current_checksum == last_checksum
          result = temp[:model]
        end
      end
    end
    
    if !result
      # load from disk
      vt = OpenStudio::OSVersion::VersionTranslator.new
      model = vt.loadModel(osm_path)
        
      if model.empty?
        @osms[osm_path] = nil
      else
        result = model.get
        @osms[osm_path] = {:checksum => current_checksum, :model => result}
      end
    end
    
    return result
  end
  
  # returns nil or OpenStudio::BCLMeasure from path, force_reload forces the measure.xml to be read from disk
  def get_measure(measure_path, force_reload)
  
    result = nil
    if !force_reload
      # load from cache
      result = @measures[measure_path]
    end

    if result.nil?
      # load from disk
      measure = OpenStudio::BCLMeasure.load(measure_path)
      if measure.empty?
        @measures[measure_path] = nil
      else
        result = measure.get
        @measures[measure_path] = result
      end
    end
    
    return result
  end
  
  # takes an OpenStudio::BCLMeasure as input, checks for updates and saves if needed
  def check_for_measure_update(measure_path, measure)
  
    # see if there are updates, want to make sure to perform both checks so do outside of conditional
    file_updates = measure.checkForUpdatesFiles # checks if any files have been updated
    xml_updates = measure.checkForUpdatesXML # only checks if xml as loaded has been changed since last save
    
    if file_updates || xml_updates
    
      # try to load the ruby measure
      info = get_measure_info(measure)
      info.update(measure)

      measure.save
      @measures[measure_path] = result
      return true
    end
    
    return false
  end
  
  # returns OpenStudio::Ruleset::RubyUserScriptInfo 
  def get_measure_info(measure, model, workspace)
    # try to load the ruby measure
    info = nil
    begin
      info = OpenStudio::Ruleset.getInfo(measure, model, workspace)
    rescue Exception => e  
      info = OpenStudio::Ruleset::RubyUserScriptInfo.new(e.message)
    end
    
    return info
  end
  
  def get_arguments_from_measure(measure)
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
          arg[:default_value] = argument.defaultValue.get if argument.defaultValue.is_initialized
        
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
          arg[:choice_values] = argument.choiceValues.join(',')
          arg[:choice_display_names] = argument.choiceDisplayNames.join(',')
        
        when 'Path'
          arg[:default_value] = argument.defaultValue.get if argument.defaultValue.is_initialized
        end
        

        result << arg
      end
    rescue
      return get_arguments_from_measure_info(get_measure_info(measure, OpenStudio::Model::OptionalModel.new, OpenStudio::OptionalWorkspace.new))
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
        arg[:default_value] = argument.defaultValueAsQuantity if argument.hasDefaultValue
        
      elsif type == "Integer".to_OSArgumentType
        arg[:units] = argument.units.get if argument.units.is_initialized
        arg[:default_value] = argument.defaultValueAsInteger if argument.hasDefaultValue
        
      elsif type == "String".to_OSArgumentType
        arg[:default_value] = argument.defaultValueAsString if argument.hasDefaultValue
      
      elsif type == "Choice".to_OSArgumentType
        arg[:default_value] = argument.defaultValueAsString if argument.hasDefaultValue
          arg[:choice_values] = argument.choiceValues.join(',')
          arg[:choice_display_names] = argument.choiceValueDisplayNames.join(',')
          
      elsif type == "Path".to_OSArgumentType
        arg[:default_value] = argument.defaultValueAsPath if argument.hasDefaultValue
        
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
    result[:tags] = measure.tags.join(',')
    
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
      result[:arguments] = get_arguments_from_measure(measure)
    end
    
    return result
  end
  
  def do_POST (request, response)

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
          
            # try to get the measure
            measure = get_measure(measure_dir, true)
            if measure.nil?
              #puts "Directory #{measure_dir} is not a measure"
            else
              updated = check_for_measure_update(measure_dir, measure)
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

        measure = get_measure(measure_dir, false)
        if measure.nil?
          raise "Cannot load measure at '#{measure_dir}'"
        end
        
        model = OpenStudio::Model::OptionalModel.new()
        if osm_path
          model = get_model(osm_path, false)
          if model.nil?
            raise "Cannot load model at '#{osm_path}'"
          end
        end
        
        info = get_measure_info(measure, model, OpenStudio::OptionalWorkspace.new())
   
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
        
        old_measure = get_measure(old_measure_dir, true)
        if old_measure.nil?
          raise "Cannot load measure at '#{old_measure_dir}'"
        end
        
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

  end
  
end

server = WEBrick::HTTPServer.new(:Port => 1234)

server.mount "/", MyServlet

trap("INT") {
    server.shutdown
}

server.start