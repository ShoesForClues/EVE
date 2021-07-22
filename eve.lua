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
local math_max   = math.max
local math_min   = math.min

local table_remove = table.remove

local bit = bit32 or require("bit")

local bit_lshift = bit.lshift
local bit_rshift = bit.rshift
local bit_and    = bit.band
local bit_or     = bit.bor
local bit_xor    = bit.bxor
local bit_not    = bit.bnot

-------------------------------------------------------------------------------

local eve={
	version = "0.0.7"
}

-------------------------------------------------------------------------------

local function position_to_id(x,y,z,w,d)
	return x+w*(y+d*z)
end

local function id_to_position(id,w,d)
	return
		id%d,
		math_floor(id/d)%w,
		math_floor(id/(w*d))
end

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

local function dissolve_boundaries(
	asx,asy,asz,aex,aey,aez,
	bsx,bsy,bsz,bex,bey,bez
)
	local x_aligned = asx==bsx or aex==bex
	local y_aligned = asy==bsy or aey==bey
	local z_aligned = asz==bsz or aez==bez
	
	local alignments=(
		(x_aligned and 1 or 0)+
		(y_aligned and 1 or 0)+
		(z_aligned and 1 or 0)
	)
	
	if alignments~=2 then
		return
	end
	
	local avx = aex-asx
	local bvx = bex-bsx
	
	local sx = math_min(asx,bsx)
	local ex = math_max(aex,bex)
	
	if not x_aligned and ex-sx~=avx+bvx+1 then
		return
	elseif x_aligned and avx~=bvx then
		return
	end
	
	local avy = aey-asy
	local bvy = bey-bsy
	
	local sy = math_min(asy,bsy)
	local ey = math_max(aey,bey)
	
	if not y_aligned and ey-sy~=avy+bvy+1 then
		return
	elseif y_aligned and avy~=bvy then
		return
	end
	
	local avz = aez-asz
	local bvz = bez-bsz
	
	local sz = math_min(asz,bsz)
	local ez = math_max(aez,bez)
	
	if not z_aligned and ez-sz~=avz+bvz+1 then
		return
	elseif z_aligned and avz~=bvz then
		return
	end
	
	return sx,sy,sz,ex,ey,ez
end

local function dissolve_mesh(mesh)
	local mesh_count=#mesh+1
	
	while #mesh~=mesh_count do
		mesh_count=#mesh
		
		for a=#mesh,1,-1 do
			local mesh_a=mesh[a]
			
			if mesh_a and mesh_a.class.mesh_type~="isolate" then
				for b=#mesh,1,-1 do
					local mesh_b=mesh[b]
					
					if mesh_b and mesh_b~=mesh_a and mesh_b.id==mesh_a.id then
						local sx,sy,sz,ex,ey,ez=dissolve_boundaries(
							mesh_a.sx,mesh_a.sy,mesh_a.sz,
							mesh_a.ex,mesh_a.ey,mesh_a.ez,
							mesh_b.sx,mesh_b.sy,mesh_b.sz,
							mesh_b.ex,mesh_b.ey,mesh_b.ez
						)
						
						if sx then
							mesh_a.sx = sx
							mesh_a.sy = sy
							mesh_a.sz = sz
							mesh_a.ex = ex
							mesh_a.ey = ey
							mesh_a.ez = ez
							
							mesh_a.faces=bit_or(mesh_a.faces,mesh_b.faces)
							
							table_remove(mesh,b)
						end
					end
				end
			end
		end
	end
	
	return mesh
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

function map.set_chunk(map_,ai,ci,chunk)
	local attribute=map_.data[ai] or (chunk~=nil and {})
	
	if not attribute then
		return
	end
	
	attribute[ci] = next(chunk) and chunk or nil
	map_.data[ai] = next(attribute) and attribute or nil
end

function map.get_chunk(map_,ai,ci)
	local attribute=map_.data[ai]
	
	if not attribute then
		return
	end
	
	return attribute[ci]
end

function map.export(map_)
	
end

function map.import(map_,binary)
	
end

-------------------------------------------------------------------------------

local handler={}; handler.__index = handler

function handler.new(map)
	return setmetatable({
		map        = map,
		classes    = {},
		meshes     = {},
		mesh_queue = {},
		events     = {
			["voxel_created"] = {},
			["voxel_deleted"] = {},
			["voxel_updated"] = {},
			["mesh_created"]  = {},
			["mesh_deleted"]  = {},
			["mesh_updated"]  = {}
		}
	},handler)
end

function handler.register_event(handler_,name,callback)
	local events = handler_.events
	local event  = events[name]
	
	assert(event,"Event does not exist.")
	
	for _,callback_ in ipairs(event) do
		if callback_==callback then
			return error("Callback is already registered")
		end
	end
	
	event[#event+1]=callback
end

function handler.unregister_event(handler_,name,callback)
	local events = handler_.events
	local event  = events[name]
	
	assert(event,"Event does not exist.")
	
	for i,callback_ in ipairs(event) do
		if callback_==callback then
			table_remove(event,i)
			break
		end
	end
end

function handler.invoke_event(handler_,name,...)
	local events = handler_.events
	local event  = events[name]
	
	for i,callback in ipairs(event) do
		callback(...)
	end
end

function handler.add_class(handler_,id,mesh_type)
	--Mesh types: blend, group, isolate
	handler_.classes[id]={
		mesh_type=mesh_type or "blend"
	}
end

function handler.create_chunk(handler_,cx,cy,cz,generator)
	local map_    = handler_.map
	local classes = handler_.classes
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	local lcx = cx*cw
	local lcy = cy*ch
	local lcz = cz*cd
	
	local ci = position_to_id(cx,cy,cz,pw,pd)+1
	
	for lz=0,cd-1 do for ly=0,ch-1 do for lx=0,cw-1 do
		local li = lx+cw*(ly+cd*lz)+1
		
		local x = lx+lcx
		local y = ly+lcy
		local z = lz+lcz
		
		local id = generator(x,y,z)
		
		if id then
			map_:set_voxel("id",ci,li,id)
			map_:set_voxel(id,ci,li,true)
		end
	end end end
	
	local chunk = map_:get_chunk("id",ci)
	
	if not chunk then
		return
	end
	
	for li,id in pairs(chunk) do
		local lx,ly,lz = id_to_position(li-1,cw,cd)
		
		local faces=0x3f --6 bits
		
		for oz=-1,1 do for oy=-1,1 do for ox=-1,1 do
			if (
				(ox~=0 and oy==0 and oz==0) or
				(ox==0 and oy~=0 and oz==0) or
				(ox==0 and oy==0 and oz~=0)
			) then
				local nx = lcx+lx+ox
				local ny = lcy+ly+oy
				local nz = lcz+lz+oz
				
				local nci = position_to_chunk_id(nx,ny,nz,cw,ch,cd,pw,pd)+1
				local nli = position_to_local_id(nx,ny,nz,cw,ch,cd)+1
				local nid = map_:get_voxel("id",nci,nli)
				
				if nid then
					if (
						classes[nid].mesh_type=="blend" or 
						(classes[id].mesh_type=="group" and id==nid)
					) then
						faces=set_bit_face(faces,ox,oy,oz,0)
						
						if nci~=ci and (
							classes[id].mesh_type=="blend" or 
							(classes[id].mesh_type=="group" and id==nid)
						) then
							local nfaces=set_bit_face(
								map_:get_voxel("visible",nci,nli) or 0x3f,
								-ox,-oy,-oz,
								0
							)
							
							map_:set_voxel(
								"visible",nci,nli,
								nfaces>0 and nfaces or nil
							)
						end
					end
				end
			end
		end end end
		
		if faces>0 then
			map_:set_voxel("visible",ci,li,faces)
		end
	end
end

function handler.create_voxel(handler_,x,y,z,id)
	local map_    = handler_.map
	local classes = handler_.classes
	local meshes  = handler_.meshes
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	if x<0 or y<0 or z<0 or x>cw*pw or y>ch*ph or z>cd*pd then
		return
	end
	
	local ci = position_to_chunk_id(x,y,z,cw,ch,cd,pw,pd)+1
	local li = position_to_local_id(x,y,z,cw,ch,cd)+1
	
	if map_:get_voxel("id",ci,li) then
		return
	end
	
	local class     = classes[id]
	local mesh_type = class.mesh_type
	
	map_:set_voxel("id",ci,li,id)
	map_:set_voxel(id,ci,li,true)
	
	handler_:invoke_event("voxel_created",x,y,z,ci,li,id)
	
	local mesh = meshes[ci]
	
	if mesh then
		local cx,cy,cz = id_to_position(ci-1,pw,pd)
		
		local lx = x%cw
		local ly = y%ch
		local lz = z%cd
		
		handler_:queue_mesh(cx,cy,cz,lx,ly,lz)
	end
	
	local faces = 0x3f
	
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
			
			local ncx,ncy,ncz = id_to_position(nci-1,pw,pd)
			
			local nlx = nx%cw
			local nly = ny%ch
			local nlz = nz%cd
			
			if nid then
				if (
					classes[nid].mesh_type=="blend" or 
					(classes[id].mesh_type=="group" and id==nid)
				) then
					faces=set_bit_face(faces,ox,oy,oz,0)
					
					if (
						classes[id].mesh_type=="blend" or 
						(classes[id].mesh_type=="group" and id==nid)
					) then
						local nfaces=set_bit_face(
							map_:get_voxel("visible",nci,nli) or 0x3f,
							-ox,-oy,-oz,
							0
						)
						
						map_:set_voxel(
							"visible",nci,nli,
							nfaces>0 and nfaces or nil
						)
					end
				end
			end
			
			handler_:queue_mesh(ncx,ncy,ncz,nlx,nly,nlz)
		end
	end end end
	
	if faces>0 then
		map_:set_voxel("visible",ci,li,faces)
	end
end

function handler.delete_voxel(handler_,x,y,z)
	local map_    = handler_.map
	local classes = handler_.classes
	local meshes  = handler_.meshes
	
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
	
	handler_:invoke_event("voxel_deleted",x,y,z,ci,li,id)
	
	local mesh = meshes[ci]
	
	if mesh then
		local cx,cy,cz = id_to_position(ci-1,pw,pd)
		
		local lx = x%cw
		local ly = y%ch
		local lz = z%cd
		
		handler_:queue_mesh(cx,cy,cz,lx,ly,lz)
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
			
			local ncx,ncy,ncz = id_to_position(nci-1,pw,pd)
			
			local nlx = nx%cw
			local nly = ny%ch
			local nlz = nz%cd
			
			if nid then
				map_:set_voxel(
					"visible",nci,nli,
					set_bit_face(
						map_:get_voxel("visible",nci,nli) or 0x3f,
						-ox,-oy,-oz,
						1
					)
				)
			end
			
			handler_:queue_mesh(ncx,ncy,ncz,nlx,nly,nlz)
		end
	end end end
end

function handler.set_voxel_attribute(handler_,x,y,z,attribute,value)
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
	
	handler_:invoke_event("voxel_updated",x,y,z,attribute,value)
end

function handler.get_voxel_attribute(handler_,x,y,z,attribute)
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

function handler.create_mesh(handler_,cx,cy,cz)
	local map_    = handler_.map
	local meshes  = handler_.meshes
	local classes = handler_.classes
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	local ci = position_to_id(cx,cy,cz,pw,pd)+1
	
	if meshes[ci] then
		return
	end
	
	local chunk   = map_:get_chunk("id",ci)
	local visible = map_:get_chunk("visible",ci)
	
	if not chunk or not visible then
		return
	end
	
	local mesh={}
	
	--Create initial mesh
	local appended={}
	for li,faces in pairs(visible) do
		if not appended[li] then
			appended[li]=true
			
			local id = chunk[li]
			local lx,ly,lz = id_to_position(li-1,cw,cd)
			
			local boundary={
				id    = id,
				class = classes[id],
				faces = faces,
				sx    = lx,
				sy    = ly,
				sz    = lz,
				ex    = lx,
				ey    = ly,
				ez    = lz
			}
			
			for x=lx,0,-1 do
				local nli    = position_to_id(x,ly,lz,cw,cd)+1
				local nid    = chunk[nli]
				local nfaces = visible[nli]
				
				if nid==id and nfaces and not appended[nli] then
					appended[nli]=true
					boundary.faces=bit_or(boundary.faces,nfaces)
				else
					boundary.sx=x
					break
				end
			end
			
			for x=lx,cw-1 do
				local nli    = position_to_id(x,ly,lz,cw,cd)+1
				local nid    = chunk[nli]
				local nfaces = visible[nli]
				
				if nid==id and nfaces and not appended[nli] then
					appended[nli]=true
					boundary.faces=bit_or(boundary.faces,nfaces)
				else
					boundary.ex=x
					break
				end
			end
			
			mesh[#mesh+1]=boundary
		end
	end
	
	if not next(mesh) then --This should never run
		return
	end
	
	meshes[ci]=dissolve_mesh(mesh)
	
	handler_:invoke_event("mesh_created",cx,cy,cz,ci,mesh)
	
	return mesh
end

function handler.delete_mesh(handler_,cx,cy,cz)
	local map_       = handler_.map
	local meshes     = handler_.meshes
	local mesh_queue = handler_.mesh_queue
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	local ci = position_to_id(cx,cy,cz,pw,pd)+1
	
	local mesh = meshes[ci]
	
	if not mesh then
		return
	end
	
	meshes[ci]     = nil
	mesh_queue[ci] = nil
	
	handler_:invoke_event("mesh_deleted",cx,cy,cz,ci,mesh)
end

function handler.queue_mesh(handler_,cx,cy,cz,lx,ly,lz)
	local map_       = handler_.map
	local meshes     = handler_.meshes
	local mesh_queue = handler_.mesh_queue
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	local ci = position_to_id(cx,cy,cz,pw,pd)+1
	
	local mesh  = meshes[ci]
	local chunk = map_:get_chunk("id",ci)
	
	if not chunk then
		handler_:delete_mesh(cx,cy,cz)
		return
	end
	
	if not mesh then
		return
	end
	
	local queue = mesh_queue[ci] or {}
	
	local li = position_to_id(lx,ly,lz,cw,cd)+1
	
	queue[li]=true
	
	mesh_queue[ci]=queue
end

function handler.update_meshes(handler_)
	local map_       = handler_.map
	local meshes     = handler_.meshes
	local mesh_queue = handler_.mesh_queue
	local classes    = handler_.classes
	
	local cw = map_.chunk_width
	local ch = map_.chunk_height
	local cd = map_.chunk_depth
	
	local pw = map_.partition_width
	local ph = map_.partition_height
	local pd = map_.partition_depth
	
	for ci,queue in pairs(mesh_queue) do
		local cx,cy,cz = id_to_position(ci-1,pw,pd)
		
		local mesh  = meshes[ci]
		local chunk = map_:get_chunk("id",ci)
		
		for li,_ in pairs(queue) do
			local lx,ly,lz = id_to_position(li-1,cw,cd)
			
			local appended=false
			
			for i=#mesh,1,-1 do
				local boundary=mesh[i]
				
				local sx = boundary.sx
				local sy = boundary.sy
				local sz = boundary.sz
				local ex = boundary.ex
				local ey = boundary.ey
				local ez = boundary.ez
				
				local in_bound=(
					lx>=sx and ly>=sy and lz>=sz and
					lx<=ex and ly<=ey and lz<=ez
				)
				
				if in_bound then
					table_remove(mesh,i)
					appended=true
					
					for bz=sz,ez do for by=sy,ey do
						local new_boundary=nil
						
						for bx=sx,ex do
							local bli=position_to_id(bx,by,bz,cw,cd)+1
			
							local id=chunk[bli]
							
							if id then
								local class=classes[id]
								
								local faces = handler_:get_voxel_attribute(
									cx*cw+bx,
									cy*ch+by,
									cz*cd+bz,
									"visible"
								)
								
								if faces then
									if new_boundary and new_boundary.id~=id then
										mesh[#mesh+1]=new_boundary
										new_boundary=nil
									end
									
									if new_boundary then
										new_boundary.ex    = bx
										new_boundary.faces = bit_or(new_boundary.faces,faces)
									else
										new_boundary={
											id    = id,
											class = class,
											faces = faces,
											sx    = bx,
											sy    = by,
											sz    = bz,
											ex    = bx,
											ey    = by,
											ez    = bz
										}
										
										if class.mesh_type=="isolate" then
											mesh[#mesh+1]=new_boundary
											new_boundary=nil
										end
									end
								elseif new_boundary then
									mesh[#mesh+1]=new_boundary
									new_boundary=nil
								end
							elseif new_boundary then
								mesh[#mesh+1]=new_boundary
								new_boundary=nil
							end
						end
						
						if new_boundary then
							mesh[#mesh+1]=new_boundary
						end
					end end
				end
			end
			
			if not appended then
				local id=chunk[li]
					
				if id then
					local class=classes[id]
					
					local faces = handler_:get_voxel_attribute(
						cx*cw+lx,
						cy*ch+ly,
						cz*cd+lz,
						"visible"
					)
					
					if faces then
						mesh[#mesh+1]={
							id    = id,
							class = class,
							faces = faces,
							sx    = lx,
							sy    = ly,
							sz    = lz,
							ex    = lx,
							ey    = ly,
							ez    = lz
						}
					end
				end
			end
		end
		
		dissolve_mesh(mesh)
		
		if not next(mesh) then
			meshes[ci]=nil
			handler_:invoke_event("mesh_deleted",cx,cy,cz,ci,mesh)
		else
			handler_:invoke_event("mesh_updated",cx,cy,cz,ci,mesh)
		end
		
		mesh_queue[ci]=nil
	end
end

-------------------------------------------------------------------------------

eve.position_to_chunk_id           = position_to_chunk_id
eve.position_to_local_id           = position_to_local_id
eve.chunk_and_local_id_to_position = chunk_and_local_id_to_position
eve.id_to_position                 = id_to_position

eve.faces_to_bits = faces_to_bits
eve.bits_to_faces = bits_to_faces
eve.set_bit_face  = set_bit_face

eve.dissolve_boundaries = dissolve_boundaries

eve.map     = map
eve.handler = handler

return eve