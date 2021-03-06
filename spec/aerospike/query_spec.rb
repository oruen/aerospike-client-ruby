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

require "spec_helper"
require "aerospike/query/statement"

describe Aerospike::Client do

    let(:udf_body) do
      " local function map_record(record)
          -- Add name and age to returned map.
          -- Could add other record bins here as well.
          return map {bin1=record.bin1, bin2=record['bin2']}
        end

        function filter_records(stream)

          local function filter_name(record)
            return true
          end

          return stream : filter(filter_name) : map(map_record)
        end

        function filter_records_param(stream, value)

          local function filter_name(record)
            return record['bin2'] > value
          end

          return stream : filter(filter_name) : map(map_record)
        end"
    end

  describe "Query operations" do

    before :all do

      @client = described_class.new(Support.host, Support.port, :user => Support.user, :password => Support.password)
      @record_count = 1000

      for i in 1..@record_count
        key = Aerospike::Key.new('test', 'test998', i)

        bin_map = {
          'bin1' => "value#{i}",
          'bin2' => i,
          'bin4' => ['value4', {'map1' => 'map val'}],
          'bin5' => {'value5' => [124, "string value"]},
        }

        @client.put(key, bin_map)

        expect(@client.exists(key)).to eq true
      end

      index_task = @client.create_index(
        key.namespace,
        key.set_name,
        "index_int_bin2",
        'bin2', :numeric
        )

      expect(index_task.wait_till_completed).to be true
      expect(index_task.completed?).to be true

      index_task = @client.create_index(
        key.namespace,
        key.set_name,
        "index_str_bin1",
        'bin1', :string
        )

      expect(index_task.wait_till_completed).to be true
      expect(index_task.completed?).to be true
    end

    after :all do
      @client.close
    end

    context "No Filter == Scan" do

      it "should return all records" do
        rs = @client.query(Aerospike::Statement.new('test', 'test998', ))

        i = 0
        rs.each do |rec|
          i +=1
          expect(rec.bins['bin1']).to eq "value#{rec.bins['bin2']}"
        end

        expect(i).to eq @record_count

      end # it

    end # context

    context "Equal Filter" do

      context "Numeric Bins" do

        it "should return relevent records" do
          stmt = Aerospike::Statement.new('test', 'test998', ['bin1', 'bin2'])
          stmt.filters = [Aerospike::Filter.Equal('bin2', 1)]
          rs = @client.query(stmt)

          i = 0
          rs.each do |rec|
            i +=1
            expect(rec.bins['bin1']).to eq "value#{rec.bins['bin2']}"
            expect(rec.bins.length).to eq 2
          end

          expect(i).to eq 1

        end # it

      end # context

      context "String Bins" do

        it "should return relevent records" do
          stmt = Aerospike::Statement.new('test', 'test998')
          stmt.filters = [Aerospike::Filter.Equal('bin1', 'value1')]
          rs = @client.query(stmt)

          i = 0
          rs.each do |rec|
            i +=1
            expect(rec.bins['bin1']).to eq "value#{rec.bins['bin2']}"
          end

          expect(i).to eq 1

        end # it

      end # context

    end # context

    context "Range Filter" do

      context "Numeric Bins" do

        it "should return relevent records" do
          stmt = Aerospike::Statement.new('test', 'test998')
          stmt.filters = [Aerospike::Filter.Range('bin2', 10, 100)]
          rs = @client.query(stmt)

          i = 0
          rs.each do |rec|
            i +=1
            expect(rec.bins['bin1']).to eq "value#{rec.bins['bin2']}"
          end

          expect(i).to eq 91

        end # it

      end # context

    end # context

    context "With A Stream UDF Query" do

      it "should return relevent records from UDF without any arguments" do

        register_task = @client.register_udf(udf_body, "udf_empty.lua", Aerospike::Language::LUA)

        expect(register_task.wait_till_completed).to be true
        expect(register_task.completed?).to be true

        stmt = Aerospike::Statement.new('test', 'test998')
        stmt.filters = [Aerospike::Filter.Range('bin2', 10, 100)]
        stmt.set_aggregate_function('udf_empty', 'filter_records', [], true)

        rs = @client.query(stmt)

        i = 0
        rs.each do |rec|
          i +=1
          res = rec.bins["SUCCESS"]
          expect(res['bin1']).to eq "value#{res['bin2']}"
        end

        expect(i).to eq 91

      end # it

      it "should return relevent records from UDF with arguments" do

        register_task = @client.register_udf(udf_body, "udf_empty.lua", Aerospike::Language::LUA)

        expect(register_task.wait_till_completed).to be true
        expect(register_task.completed?).to be true

        stmt = Aerospike::Statement.new('test', 'test998')
        stmt.filters = [Aerospike::Filter.Range('bin2', 10, 100)]

        filter_value = 90
        stmt.set_aggregate_function('udf_empty', 'filter_records_param', [filter_value], true)

        rs = @client.query(stmt)

        i = 0
        rs.each do |rec|
          i +=1
          res = rec.bins["SUCCESS"]
          expect(res['bin1']).to eq "value#{res['bin2']}"
          expect(res['bin2']).to be > filter_value
        end

        expect(i).to eq 10

      end # it

    end # context

  end # describe

end # describe
