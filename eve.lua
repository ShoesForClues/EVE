--[[
Easy Voxel Engine

MIT License

Copyright (c) 2021 Shoelee

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
]]

local math_floor = math.floor
local math_ceil  = math.ceil

local bit = bit32 or require("bit")

local bit_lshift = bit.lshift
local bit_rshift = bit.rshift
local bit_and    = bit.band
local bit_or     = bit.bor
local bit_xor    = bit.bxor
local bit_not    = bit.bnot

-------------------------------------------------------------------------------

local eve={
	version = "0.0.3"
}

-------------------------------------------------------------------------------

local function position_to_chunk_id(x,y,z,cw,ch,cd,pw,pd)
	local cx = math_floor(x/cw)
	local cy = math_floor(y/ch)
	local cz = math_floor(z/cd)
	
	return cx+pw*(cy+pd*cz)
end

local function position_to_local_id(x,y,z,cw,ch,cd)
	local lx = x%cw
	local ly = y%ch
	local lz = z%cd
	
	return lx+cw*(ly+cd*lz)
end

local function chunk_and_local_id_to_position(ci,li,cw,ch,cd,pw,pd)
	local cx = ci%pd
	local cy = math_floor(ci/pd)%pw
	local cz = math_floor(ci/(pw*pd))
	
	local lx = li%cd
	local ly = math_floor(li/cd)%cw
	local lz = math_floor(li/(cw*cd))
	
	return cx*cw+lx,cy*ch+ly,cz*cd+lz
end

local function faces_to_bits(f,b,l,r,u,d)
	return bit_or(f*32,b*16,l*8,r*4,u*2,d*1)
end

local function bits_to_faces(n)
	return
		bit_and(bit_rshift(n,5),1),
		bit_and(bit_rshift(n,4),1),
		bit_and(bit_rshift(n,3),1),
		bit_and(bit_rshift(n,2),1),
		bit_and(bit_rshift(n,1),1),
		bit_and(n,1)
end

local function set_bit_face(n,x,y,z,v)
	local offset=(
		((x==0 and y==0 and z==-1) and 5) or
		((x==0 and y==0 and z==1) and 4) or
		((x==-1 and y==0 and z==0) and 3) or
		((x==1 and y==0 and z==0) and 2) or
		((x==0 and y==1 and z==0) and 1) or
		((x==0 and y==-1 and z==0) and 0)
	)
	
	return
		bit_and(bit_rshift(n,offset),1)==v and n or 
		bit_xor(n,2^offset)
end

-------------------------------------------------------------------------------

local map={}; map.__index = map

function map.new(cw,ch,cd,pw,ph,pd,data)
	return setmetatable({
		chunk_width      = cw or 16,
		chunk_height     = ch or 16,
		chunk_depth      = cd or 16,
		partition_width  = pw or 4096,
		partition_height = ph or 4096,
		partition_depth  = pd or 4096,
		data             = data or {}
	},map)
end

function map.set_voxel(map_,ai,ci,li,value)
	local attribute=map_.data[ai] or (value~=nil and {})
	
	if not attribute then
		return
	end
	
	local chunk=attribute[ci] or (value~=nil and {})
	
	if not chunk then
		return
	end
	
	chunk[li]     = value
	attribute[ci] = next(chunk) and chunk or nil
	map_.data[ai] = next(attribute) and attribute or nil
end

function map.get_voxel(map_,ai,ci,li)
	local attribute=map_.data[ai]
	
	if not attribute then
		return
	end
	
	if not attribute[ci] then
		return
	end
	
	return attribute[ci][li]
end

function map.export(map_)
	
end

function map.import(map_,raw)
	
end

-------------------------------------------------------------------------------

local handler={}; handler.__index = handler

function handler.new(map)
	return setmetatable({
		map      = map,
		classes  = {},
		rendered = {}
	},handler)
end

function handler.add_class(handler_,id,mesh_type)
	--Mesh types: blend, group, isolate
	handler_.classes[id]={
		mesh_type=mesh_type or "blend"
	}
end

function handler.add_voxel(handler_,x,y,z,id)
	x,y,z=x-1,y-1,z-1
	
	local map_    = handler_.map
	local classes = handler_.classes
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	local ci = position_to_chunk_id(x,y,z,cw,ch,cd,pw,pd)+1
	local li = position_to_local_id(x,y,z,cw,ch,cd)+1
	
	if map_:get_voxel("id",ci,li) then
		return
	end
	
	local class     = classes[id]
	local mesh_type = class.mesh_type
	
	map_:set_voxel("id",ci,li,id)
	map_:set_voxel(id,ci,li,true)
	
	local faces=0x3f --6 bits: front,back,left,right,up,down
	
	for oz=-1,1 do for oy=-1,1 do for ox=-1,1 do
		if (
			(ox~=0 and oy==0 and oz==0) or
			(ox==0 and oy~=0 and oz==0) or
			(ox==0 and oy==0 and oz~=0)
		) then
			local nx = x+ox
			local ny = y+oy
			local nz = z+oz
			
			local nci = position_to_chunk_id(nx,ny,nz,cw,ch,cd,pw,pd)+1
			local nli = position_to_local_id(nx,ny,nz,cw,ch,cd)+1
			
			local nid = map_:get_voxel("id",nci,nli)
			
			if nid then
				local neighbor_class     = classes[nid]
				local neighbor_mesh_type = neighbor_class.mesh_type
				local neighbor_faces     = map_:get_voxel("faces",nci,nli)
				
				if mesh_type=="blend" then
					neighbor_faces=set_bit_face(
						neighbor_faces,
						-ox,-oy,-oz,
						0
					)
				end
				if neighbor_mesh_type=="blend" then
					faces=set_bit_face(
						faces,
						ox,oy,oz,
						0
					)
				end
				if mesh_type=="group" and id==nid then
					faces=set_bit_face(
						faces,
						ox,oy,oz,
						0
					)
					neighbor_faces=set_bit_face(
						neighbor_faces,
						-ox,-oy,-oz,
						0
					)
				end
				
				map_:set_voxel("faces",nci,nli,neighbor_faces)
				
				if neighbor_faces>0 then
					map_:set_voxel("visible",nci,nli,true)
					map_:set_voxel("invisible",nci,nli,nil)
				else
					map_:set_voxel("visible",nci,nli,nil)
					map_:set_voxel("invisible",nci,nli,true)
				end
			end
		end
	end end end
	
	map_:set_voxel("faces",ci,li,faces)
	
	if faces>0 then
		map_:set_voxel("visible",ci,li,true)
	else
		map_:set_voxel("invisible",ci,li,true)
	end
end

function handler.delete_voxel(handler_,x,y,z)
	x,y,z=x-1,y-1,z-1
	
	local map_    = handler_.map
	local classes = handler_.classes
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	local ci = position_to_chunk_id(x,y,z,cw,ch,cd,pw,pd)+1
	local li = position_to_local_id(x,y,z,cw,ch,cd)+1
	
	local id=map_:get_voxel("id",ci,li)
	
	if not id then
		return
	end
	
	local class     = classes[id]
	local mesh_type = class.mesh_type
	
	for ai,_ in pairs(map_.data) do
		if map_:get_voxel(ai,ci,li)~=nil then
			map_:set_voxel(ai,ci,li,nil)
		end
	end
	
	for oz=-1,1 do for oy=-1,1 do for ox=-1,1 do
		if (
			(ox~=0 and oy==0 and oz==0) or
			(ox==0 and oy~=0 and oz==0) or
			(ox==0 and oy==0 and oz~=0)
		) then
			local nx = x+ox
			local ny = y+oy
			local nz = z+oz
			
			local nci = position_to_chunk_id(nx,ny,nz,cw,ch,cd,pw,pd)+1
			local nli = position_to_local_id(nx,ny,nz,cw,ch,cd)+1
			
			local nid = map_:get_voxel("id",nci,nli)
			
			if nid then
				local neighbor_class     = classes[nid]
				local neighbor_mesh_type = neighbor_class.mesh_type
				local neighbor_faces     = map_:get_voxel("faces",nci,nli)
				
				if (
					mesh_type=="blend" or 
					(mesh_type=="group" and id==nid)
				) then
					neighbor_faces=set_bit_face(
						neighbor_faces,
						-ox,-oy,-oz,
						1
					)
				end
				
				map_:set_voxel("faces",nci,nli,neighbor_faces)
				
				if neighbor_faces>0 then
					map_:set_voxel("visible",nci,nli,true)
					map_:set_voxel("invisible",nci,nli,nil)
				else
					map_:set_voxel("visible",nci,nli,nil)
					map_:set_voxel("invisible",nci,nli,true)
				end
			end
		end
	end end end
end

function handler.set_voxel_attribute(handler_,x,y,z,attribute,value)
	x,y,z=x-1,y-1,z-1
	
	local map_=handler_.map
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	local ci = position_to_chunk_id(x,y,z,cw,ch,cd,pw,pd)+1
	local li = position_to_local_id(x,y,z,cw,ch,cd)+1
	
	if not map_:get_voxel("id",ci,li) then
		return
	end
	
	map_:set_voxel(attribute,ci,li,value)
end

function handler.get_voxel_attribute(handler_,x,y,z,attribute)
	x,y,z=x-1,y-1,z-1
	
	local map_=handler_.map
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	local ci = position_to_chunk_id(x,y,z,cw,ch,cd,pw,pd)+1
	local li = position_to_local_id(x,y,z,cw,ch,cd)+1
	
	return map_:get_voxel(attribute,ci,li)
end

-------------------------------------------------------------------------------

eve.position_to_chunk_id           = position_to_chunk_id
eve.position_to_local_id           = position_to_local_id
eve.chunk_and_local_id_to_position = chunk_and_local_id_to_position

eve.faces_to_bits = faces_to_bits
eve.bits_to_faces = bits_to_faces
eve.set_bit_face  = set_bit_face

eve.map     = map
eve.handler = handler

return eve