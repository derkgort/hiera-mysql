# Class Mysql_backend
# Description: MySQL back end to Hiera.
# Author: Craig Dunn <craig@craigdunn.org>
#
class Hiera
  module Backend
    class Mysql_backend
      def initialize
        @use_jdbc = defined?(JRUBY_VERSION) ? true : false
        if @use_jdbc
          require 'jdbc/mysql'
          require 'java'
        else
          begin
            require 'mysql'
          rescue LoadError
            require 'rubygems'
            require 'mysql'
          end
        end

        Hiera.debug("mysql_backend initialized")
        Hiera.debug("JDBC mode #{@use_jdbc}")
      end


      def lookup(key, scope, order_override, resolution_type)

        Hiera.debug("mysql_backend invoked lookup")
        Hiera.debug("resolution type is #{resolution_type}")

        answer = nil

        # Parse the mysql query from the config, we also pass in key
        # to extra_data so this can be interpreted into the query
        # string
        #
        queries = [ Config[:mysql][:query] ].flatten
        queries.map! { |q| Backend.parse_string(q, scope, {"key" => key}) }

        queries.each do |mysql_query|

          results = query(mysql_query)

          unless results.empty?
            case resolution_type
            when :array
              answer ||= []
              results.each do |ritem|
                answer << Backend.parse_answer(ritem, scope)
              end
            when :hash
              answer ||= {}
              results.each do |ritem|
                parsed_result = parse_response(ritem)
                answer = Backend.merge_answer(parsed_result, answer)
              end
            else
              answer = Backend.parse_answer(results[0], scope)
              break
            end
          end

        end
        answer
      end

      def parse_response(answer)
        return unless answer

        format = Config[:mysql][:output] || 'plain'
        Hiera.debug("[hiera-mysql]: Query returned data, parsing response as #{format}")

        case format
        when 'json'
          parse_json answer
        when 'yaml'
          parse_yaml answer
        else
          answer
        end
      end

      # Handlers
      # Here we define specific handlers to parse the output of the http request
      # and return its structured representation.  Currently we support YAML and JSON
      #
      def parse_json(answer)
        require 'rubygems'
        require 'json'
        JSON.parse(answer)
      end

      def parse_yaml(answer)
        require 'yaml'
        YAML.load(answer)
      end

      def query (sql)
        Hiera.debug("Executing SQL Query: #{sql}")

        data=[]
        mysql_host=Config[:mysql][:host]
        mysql_user=Config[:mysql][:user]
        mysql_pass=Config[:mysql][:pass]
        mysql_database=Config[:mysql][:database]


        if @use_jdbc
          #
          # JDBC connection handling, this will be run under jRuby
          #
          Jdbc::MySQL.load_driver
          url = "jdbc:mysql://#{mysql_host}:3306/#{mysql_database}"
          props = java.util.Properties.new
          props.set_property :user, mysql_user
          props.set_property :password, mysql_pass

          conn = com.mysql.jdbc.Driver.new.connect(url,props)
          stmt = conn.create_statement

          res = stmt.execute_query(sql)
          md = res.getMetaData
          numcols = md.getColumnCount

          Hiera.debug("Mysql Query returned #{numcols} rows")

          while ( res.next ) do
            if numcols < 2
              Hiera.debug("Mysql value : #{res.getString(1)}")
              data << res.getString(1)
            else
              row = {}
              (1..numcols).each do |c|
                row[md.getColumnName(c)] = res.getString(c)
              end
              data << row
            end
          end
        else
          #
          # Native mysql connection, for calls outside of jRuby
          #
          dbh = Mysql.new(mysql_host, mysql_user, mysql_pass, mysql_database)
          dbh.reconnect = true

          res = dbh.query(sql)
          Hiera.debug("Mysql Query returned #{res.num_rows} rows")

          if res.num_fields < 2
            res.each do |row|
              Hiera.debug("Mysql value : #{row[0]}")
              data << row[0]
            end
          else
            res.each_hash do |row|
              data << row
            end
          end
        end

        return data

      end
    end
  end
end
