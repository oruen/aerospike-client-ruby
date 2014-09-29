# encoding: utf-8
# Copyright 2014 Aerospike, Inc.
#
# Portions may be licensed to Aerospike, Inc. under one or more contributor
# license agreements.
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at http:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

require 'digest'
require 'base64'

require 'aerospike/operation'
require 'aerospike/udf'

require 'aerospike/cluster/cluster'
require 'aerospike/policy/client_policy'

require 'aerospike/command/read_command'
require 'aerospike/command/read_header_command'
require 'aerospike/command/write_command'
require 'aerospike/command/delete_command'
require 'aerospike/command/exists_command'
require 'aerospike/command/touch_command'
require 'aerospike/command/operate_command'
require 'aerospike/command/execute_command'

require 'aerospike/command/batch_command_get'
require 'aerospike/command/batch_command_exists'
require 'aerospike/command/batch_node'
require 'aerospike/command/batch_item'

require 'aerospike/task/udf_register_task'
require 'aerospike/task/udf_remove_task'

require 'aerospike/ldt/large_list'
require 'aerospike/ldt/large_map'
require 'aerospike/ldt/large_set'
require 'aerospike/ldt/large_stack'

module Aerospike

  # make sure threads abort on exceptions
  Thread.abort_on_exception=true

  class Client

    attr_accessor :default_policy, :default_write_policy

    def initialize(host, port, opt=nil)
      @default_policy = Policy.new
      @default_write_policy = WritePolicy.new

      policy = opt_to_client_policy(opt)

      @cluster = Cluster.new(policy, Host.new(host, port))

      self
    end

    #  Close all client connections to database server nodes.
    def close
      @cluster.close
    end

    #  Determine if we are ready to talk to the database server cluster.
    def connected?
      @cluster.connected?
    end

    #  Return array of active server nodes in the cluster.
    def nodes
      @cluster.nodes
    end

    #  Return list of active server node names in the cluster.
    def node_names
      nodes = @cluster.nodes
      names = []

      nodes.each do |node|
        names << node.get_name
      end

      names
    end

    #-------------------------------------------------------
    # Write Record Operations
    #-------------------------------------------------------

    #  Write record bin(s).
    #  The policy specifies the transaction timeout, record expiration and how the transaction is
    #  handled when the record already exists.
    # def put(policy *WritePolicy, key *Key, bins BinMap) error {
    #   PutBins(policy, key, bin_map_to_bins(bins)...)
    # }

    #  Write record bin(s).
    #  The policy specifies the transaction timeout, record expiration and how the transaction is
    #  handled when the record already exists.
    def put(key, bins, opt=nil)
      policy = opt_to_write_policy(opt)
      command = WriteCommand.new(@cluster, policy, key, hash_to_bins(bins), Aerospike::Operation::WRITE)
      command.execute
    end

    #-------------------------------------------------------
    # Operations string
    #-------------------------------------------------------

    #  Append bin values string to existing record bin values.
    #  The policy specifies the transaction timeout, record expiration and how the transaction is
    #  handled when the record already exists.
    #  This call only works for string values.
    # def Append(policy *WritePolicy, key *Key, bins BinMap) error {
    #   return clnt.AppendBins(policy, key, bin_map_to_bins(bins)...)
    # }

    def append(key, bins, opt=nil)
      policy = opt_to_write_policy(opt)
      command = WriteCommand.new(@cluster, policy, key, hash_to_bins(bins), Aerospike::Operation::APPEND)
      command.execute
    end

    #  Prepend bin values string to existing record bin values.
    #  The policy specifies the transaction timeout, record expiration and how the transaction is
    #  handled when the record already exists.
    #  This call works only for string values.
    # def Prepend(policy *WritePolicy, key *Key, bins BinMap) error {
    #   return clnt.PrependBins(policy, key, bin_map_to_bins(bins)...)
    # }

    def prepend(key, bins, opt=nil)
      policy = opt_to_write_policy(opt)
      command = WriteCommand.new(@cluster, policy, key, hash_to_bins(bins), Aerospike::Operation::PREPEND)
      command.execute
    end

    #-------------------------------------------------------
    # Arithmetic Operations
    #-------------------------------------------------------

    #  Add integer bin values to existing record bin values.
    #  The policy specifies the transaction timeout, record expiration and how the transaction is
    #  handled when the record already exists.
    #  This call only works for integer values.
    # def Add(policy *WritePolicy, key *Key, bins BinMap) error {
    #   return clnt.AddBins(policy, key, bin_map_to_bins(bins)...)
    # }

    def add(key, bins, opt=nil)
      policy = opt_to_write_policy(opt)
      command = WriteCommand.new(@cluster, policy, key, hash_to_bins(bins), Aerospike::Operation::ADD)
      command.execute
    end

    #-------------------------------------------------------
    # Delete Operations
    #-------------------------------------------------------

    #  Delete record for specified key.
    #  The policy specifies the transaction timeout.
    def delete(key, opt=nil)
      policy = opt_to_write_policy(opt)
      command = DeleteCommand.new(@cluster, policy, key)
      command.execute
      command.existed
    end

    #-------------------------------------------------------
    # Touch Operations
    #-------------------------------------------------------

    #  Create record if it does not already exist.  If the record exists, the record's
    #  time to expiration will be reset to the policy's expiration.
    def touch(key, opt=nil)
      policy = opt_to_write_policy(opt)
      command = TouchCommand.new(@cluster, policy, key)
      command.execute
    end

    #-------------------------------------------------------
    # Existence-Check Operations
    #-------------------------------------------------------

    #  Determine if a record key exists.
    #  The policy can be used to specify timeouts.
    def exists(key, opt=nil)
      policy = opt_to_policy(opt)
      command = ExistsCommand.new(@cluster, policy, key)
      command.execute
      command.exists
    end

    #  Check if multiple record keys exist in one batch call.
    #  The returned array bool is in positional order with the original key array order.
    #  The policy can be used to specify timeouts.
    def batch_exists(keys, opt=nil)
      policy = opt_to_policy(opt)

      # same array can be used without sychronization;
      # when a key exists, the corresponding index will be marked true
      exists_array = Array.new(keys.length)

      key_map = BatchItem.generate_map(keys)

      cmd_gen = Proc.new do |node, bns|
        BatchCommandExists.new(node, bns, policy, key_map, exists_array)
      end

      batch_execute(keys, &cmd_gen)
      exists_array
    end

    #-------------------------------------------------------
    # Read Record Operations
    #-------------------------------------------------------

    #  Read record header and bins for specified key.
    #  The policy can be used to specify timeouts.
    def get(key, bin_names=[], opt=nil)
      policy = opt_to_policy(opt)

      command = ReadCommand.new(@cluster, policy, key, bin_names)
      command.execute
      command.record
    end

    #  Read record generation and expiration only for specified key.  Bins are not read.
    #  The policy can be used to specify timeouts.
    def get_header(key, opt=nil)
      policy = opt_to_policy(opt)
      command = ReadHeaderCommand.new(@cluster, policy, key)
      command.execute
      command.record
    end

    #-------------------------------------------------------
    # Batch Read Operations
    #-------------------------------------------------------

    #  Read multiple record headers and bins for specified keys in one batch call.
    #  The returned records are in positional order with the original key array order.
    #  If a key is not found, the positional record will be nil.
    #  The policy can be used to specify timeouts.
    def batch_get(keys, bin_names=[], opt=nil)
      policy = opt_to_policy(opt)

      # wait until all migrations are finished
      # TODO: implement
      # @cluster.WaitUntillMigrationIsFinished(policy.timeout)

      # same array can be used without sychronization;
      # when a key exists, the corresponding index will be set to record
      records = Array.new(keys.length)

      key_map = BatchItem.generate_map(keys)
      bin_set = {}
      bin_names.each do |bn|
        bin_set[bn] = {}
      end


      cmd_gen = Proc.new do |node, bns|
        BatchCommandGet.new(node, bns, policy, key_map, nil, records, INFO1_READ|INFO1_NOBINDATA)
      end

      batch_execute(keys, &cmd_gen)
      records
    end

    #  Read multiple record header data for specified keys in one batch call.
    #  The returned records are in positional order with the original key array order.
    #  If a key is not found, the positional record will be nil.
    #  The policy can be used to specify timeouts.
    def batch_get_header(keys, opt=nil)
      policy = opt_to_policy(opt)

      # wait until all migrations are finished
      # TODO: Fix this and implement
      # @cluster.WaitUntillMigrationIsFinished(policy.timeout)

      # same array can be used without sychronization;
      # when a key exists, the corresponding index will be set to record
      records = Array.new(keys.length)

      key_map = BatchItem.generate_map(keys)
      bin_set = {}
      bin_names.each do |bn|
        bin_set[bn] = {}
      end

      command = BatchCommandGet.new(node, bns, policy, key_map, bin_set, records, INFO1_READ | INFO_NOBINDATA)
      command.execute
    end

    #-------------------------------------------------------
    # Generic Database Operations
    #-------------------------------------------------------

    #  Perform multiple read/write operations on a single key in one batch call.
    #  An example would be to add an integer value to an existing record and then
    #  read the result, all in one database call.
    #
    #  Write operations are always performed first, regardless of operation order
    #  relative to read operations.
    def operate(key, operations, opt=nil)
      policy = opt_to_write_policy(opt)

      command = OperateCommand.new(@cluster, policy, key, operations)
      command.execute
      command.record
    end

    #-------------------------------------------------------------------
    # Large collection functions (Supported by Aerospike 3 servers only)
    #-------------------------------------------------------------------

    #  Initialize large list operator.  This operator can be used to create and manage a list
    #  within a single bin.
    #
    #  This method is only supported by Aerospike 3 servers.
    def get_large_list(key, bin_name, user_module=nil, opt=nil)
      LargeList.new(self, opt_to_write_policy(opt), key, bin_name, user_module)
    end

    #  Initialize large map operator.  This operator can be used to create and manage a map
    #  within a single bin.
    #
    #  This method is only supported by Aerospike 3 servers.
    def get_large_map(key, bin_name, user_module=nil, opt=nil)
      LargeMap.new(self, opt_to_write_policy(opt), key, bin_name, user_module)
    end

    #  Initialize large set operator.  This operator can be used to create and manage a set
    #  within a single bin.
    #
    #  This method is only supported by Aerospike 3 servers.
    def get_large_set(key, bin_name, user_module=nil, opt=nil)
      LargeSet.new(self, opt_to_write_policy(opt), key, bin_name, user_module)
    end

    #  Initialize large stack operator.  This operator can be used to create and manage a stack
    #  within a single bin.
    #
    #  This method is only supported by Aerospike 3 servers.
    def get_large_stack(key, bin_name, user_module=nil, opt=nil)
      LargeStack.new(self, opt_to_write_policy(opt), key, bin_name, user_module)
    end

    #---------------------------------------------------------------
    # User defined functions (Supported by Aerospike 3 servers only)
    #---------------------------------------------------------------

    #  Register package containing user defined functions with server.
    #  This asynchronous server call will return before command is complete.
    #  The user can optionally wait for command completion by using the returned
    #  RegisterTask instance.
    #
    #  This method is only supported by Aerospike 3 servers.
    def register_udf_from_file(client_path, server_path, language, opt=nil)
      udf_body = File.read(client_path)
      register_udf(udf_body, server_path, language, opt=nil)
    end

    #  Register package containing user defined functions with server.
    #  This asynchronous server call will return before command is complete.
    #  The user can optionally wait for command completion by using the returned
    #  RegisterTask instance.
    #
    #  This method is only supported by Aerospike 3 servers.
    def register_udf(udf_body, server_path, language, opt=nil)
      content = Base64.strict_encode64(udf_body).force_encoding('binary')

      str_cmd = "udf-put:filename=#{server_path};content=#{content};"
      str_cmd += "content-len=#{content.length};udf-type=#{language};"
      # Send UDF to one node. That node will distribute the UDF to other nodes.
      node = @cluster.random_node
      conn = node.get_connection(@cluster.connection_timeout)

      response_map = Info.request(conn, str_cmd)
      response, _ = response_map.first

      res = {}
      vals = response.split(';')
      vals.each do |pair|
        k, v = pair.split("=", 2)
        res[k] = v
      end

      if res['error']
        raise Aerospike::Exceptions::CommandRejected.new("Registration failed: #{res['error']}\nFile: #{res['file']}\nLine: #{res['line']}\nMessage: #{res['message']}")
      end

      node.put_connection(conn)
      UdfRegisterTask.new(@cluster, server_path)
    end

    #  RemoveUDF removes a package containing user defined functions in the server.
    #  This asynchronous server call will return before command is complete.
    #  The user can optionally wait for command completion by using the returned
    #  RemoveTask instance.
    #
    #  This method is only supported by Aerospike 3 servers.
    def remove_udf(udf_name, opt=nil)
      # errors are to remove errcheck warnings
      # they will always be nil as stated in golang docs
      str_cmd = "udf-remove:filename=#{udf_name};"

      # Send command to one node. That node will distribute it to other nodes.
      node = @cluster.random_node
      conn = node.get_connection(@cluster.connection_timeout)

      response_map = Info.request(conn, str_cmd)
      _, response = response_map.first

      if response == 'ok'
        UdfRemoveTask.new(@cluster, udf_name)
      else
        raise Aerospike::Exceptions::Aerospike.new(Aerospike::ResultCode::SERVER_ERROR, response)
      end
    end

    #  ListUDF lists all packages containing user defined functions in the server.
    #  This method is only supported by Aerospike 3 servers.
    def list_udf(opt=nil)
      # errors are to remove errcheck warnings
      # they will always be nil as stated in golang docs
      str_cmd = 'udf-list'

      # Send command to one node. That node will distribute it to other nodes.
      node = @cluster.random_node
      conn = node.get_connection(@cluster.connection_timeout)

      response_map = Info.request(conn, str_cmd)
      _, response = response_map.first

      vals = response.split(';')

      res = vals.map do |udf_info|
        next if udf_info.strip! == ''

        udf_parts = udf_info.split(',')
        udf = UDF.new
        udf_parts.each do |values|
          k, v = values.split('=', 2)
          case k
          when 'filename'
            udf.filename = v
          when 'hash'
            udf.hash = v
          when 'type'
            udf.language = v
          end
        end
        udf
      end


      node.put_connection(conn)

      res
    end

    #  Execute user defined function on server and return results.
    #  The function operates on a single record.
    #  The package name is used to locate the udf file location:
    #
    #  udf file = <server udf dir>/<package name>.lua
    #
    #  This method is only supported by Aerospike 3 servers.
    def execute_udf(key, package_name, function_name, args=[], opt=nil)
      policy = opt_to_write_policy(opt)

      command = ExecuteCommand.new(@cluster, policy, key, package_name, function_name, args)
      command.execute

      record = command.record

      return nil if !record || record.bins.length == 0

      result_map = record.bins

      # User defined functions don't have to return a value.
      key, obj = result_map.detect{|k, v| k.include?('SUCCESS')}
      if key
        return obj
      end

      key, obj = result_map.detect{|k, v| k.include?('FAILURE')}
      if key
        raise Aerospike::Exceptions::Aerospike.new(UDF_BAD_RESPONSE, "#{obj}")
      end

      raise Aerospike::Exception::Aerospike.new(UDF_BAD_RESPONSE, "Invalid UDF return value")
    end

    private

    def hash_to_bins(hash)
      if hash.is_a?(Bin)
        [hash]
      elsif hash.is_a?(Array)
        hash # it is a list of bins
      else
        hash.map do |k, v|
          raise Aerospike::Exceptions::Parse("bin name `#{k}` is not a string.") unless k.is_a?(String)
          Bin.new(k, v)
        end
      end
    end

    def opt_to_client_policy(opt)
      if opt.nil?
        ClientPolicy.new
      elsif opt.is_a?(ClientPolicy)
        opt
      else
        ClientPolicy.new(
          opt[:timeout],
          opt[:connection_queue_size],
          opt[:fail_if_not_connected],
        )
      end
    end

    def opt_to_policy(opt)
      if opt.nil?
        @default_write_policy
      elsif opt.is_a?(Policy)
        opt
      else
        Policy.new(
          opt[:priority],
          opt[:timeout],
          opt[:max_retiries],
          opt[:sleep_between_retries],
        )
      end
    end

    def opt_to_write_policy(opt)
      if opt.nil?
        @default_write_policy
      elsif opt.is_a?(WritePolicy)
        opt
      else
        WritePolicy.new(
          opt[:record_exists_action],
          opt[:gen_policy],
          opt[:generation],
          opt[:expiration],
          opt[:send_key]
        )
      end
    end

    def batch_execute(keys, &cmd_gen)
      batch_nodes = BatchNode.generate_list(@cluster, keys)
      threads = []

      # Use a thread per namespace per node
      batch_nodes.each do |batch_node|
        # copy to avoid race condition
        bn = batch_node
        bn.batch_namespaces.each do |bns|
          threads << Thread.new do
            command = cmd_gen.call(bn.node, bns)
            command.execute
          end
        end
      end

      threads.each { |thr| thr.join }
    end

  end # class

end #module