--!strict
-- https://github.com/redmonkye/glue

export type Unit<Interface> = Interface & {
	UnitId: string,
}

export type LifecycleHooks<T, K> = {
	onCreate: (T) -> ()? | (T, K) -> ()?,
	onStart: (T) -> ()?,
	onDestroy: (T) -> ()?
}

export type UnitDefinition<Interface, Props> = 	Interface & {
	onCreate: (Interface, Props?) -> ()?,
	onStart: (Interface) -> ()?,
	onDestroy: (Interface) -> ()?
}

export type UnitConfig = {
	loadOrder: number?,
	Dependencies: {Unit<any>}?,
}

type unit_state = "creating" | "starting" | "running" | "destroying"?
type unit_internal<Interface, Props> = {
	id: string,
	interface: Interface,
	dependencies: {string},
	defaultProps: Props?,
	hooks: LifecycleHooks<Interface, Props>,
	state: unit_state, 
	type: string
}

export type DynamicUnit<Interface> = Interface & {
	UnitId: string
}

export type DynamicUnitSpec<Interface, Props> = {
	UnitId: string,
	interface: Interface,
	defaultProps: Props
}

export type HookEvent = "onDebug" | "onCreate" | "onStart" | "onDestroy"
local HOOK_EVENTS: {HookEvent} = {"onDebug", "onCreate", "onStart", "onDestroy"}

export type HookContext = {
	Event: HookEvent,
	Unit: Unit<any>?,
	Time: number,
	unixTime: number
}

type StickOptions = {
	lifecycleLoggingEnabled: boolean?
}

type hook_ref = {	
	Id: string,
	callback: (HookContext) -> (),
	Event: { HookEvent },
}

--

local glue_state = {
	hooks = {} :: {[string]: hook_ref},
	units = {} :: {[string]: unit_internal<any, any>},
	phase = "idle" :: "idle" | "starting" | "running",
	dependency_graph = {}
}

local function glue_assert(
	assertion: boolean,
	msg: string,
	severity: "error" | "warn" | nil
): boolean
	if (assertion == false) then
		return false
	end

	local logFunc: ((...any) -> ()) = nil;
	local logSeverity = severity or "error" 

	if logSeverity == "error" then
		logFunc = error
	elseif logSeverity == "warn" then
		logFunc = warn
	end

	logFunc(`[Glue] {logSeverity:upper()}: {msg}`, if logSeverity == "error" then 2 else "")

	return true
end

local function uuid(short: boolean?)
    local str = string.gsub('xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx', '[xy]', function (c)
        return string.format('%x', (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb))
    end)

	if short then
		return str:sub(1,8)
	end

	return str
end

local function clone_table_shallow<T>(t: T): T
	local new = {} :: T & { [any]: any }

	for key, value in pairs(t :: any) do
		rawset(new, key, value)
	end

	return new
end

-- Sort function for a directed acyclic graph (DAG)
-- TODO: Add support for unit load order <UnitConfig>
-- https://interviewkickstart.com/blogs/learn/kahns-algorithm-topological-sorting
local function compile_load_order()
	local directed_unit_graph: { [string]: { string } } = glue_state.dependency_graph

	local sorted_Units = {}

	local n = 0
	local queue = {}
	local in_degrees = {}
	
	for node in directed_unit_graph do
		n += 1
		in_degrees[node] = 0
	end

	-- empty graph
	if n == 0 then
		return {}
	end

	for _, edges in directed_unit_graph do
		for _, edge in edges do
			in_degrees[edge] += 1
		end
	end

	for node, in_degree in in_degrees do
		if not (in_degree == 0) then
			continue
		end

		table.insert(queue, 1, node)
	end

	repeat
		local node = table.remove(queue) :: string

		table.insert(sorted_Units, 1, node)

		for _, edge in directed_unit_graph[node] do
			in_degrees[edge] -= 1
			if in_degrees[edge] == 0 then
				table.insert(queue, 1, edge)
			end
		end
	until #queue == 0

	return sorted_Units
end

local function update_dependency_graph()
	local directed_unit_graph = {}

	for _, unit in glue_state.units do
		directed_unit_graph[unit.id] = unit.dependencies
	end

	glue_state.dependency_graph = directed_unit_graph

	return directed_unit_graph
end

local function run_global_hooks(event: HookEvent, unit, ...)
	local hookContext = {
		Unit = unit,
		Event = event,
		Time = os.clock(),
		unixTime = os.time()
	}

	for id, hookRef: hook_ref in glue_state.hooks do
		if table.find(hookRef.Event, event) then
			hookRef.callback(hookContext, ...)
		end
	end
end

local function run_lifecycle_hook(event: HookEvent, sorted_Units: { string })
	for _, UnitId in sorted_Units do
		local unit = glue_state.units[UnitId]

		local hook = rawget(unit.hooks, event) 

		if hook then
			hook(unit.interface)
		end

		run_global_hooks(event, unit.interface)
	end
end

local function get_unit_state(unitId: string): unit_state
	return glue_state.units[unitId].state
end

local function set_unit_state(unitId: string, state: unit_state)
	glue_state.units[unitId].state = state
end

local function createHook(Event: HookEvent | { HookEvent }, fn: (HookContext) -> ()): string
	glue_assert(not (glue_state.phase == "idle"), "Cannot register hooks after glue has started.")

	local eventType = typeof(Event)

	glue_assert(not (eventType == "table" or eventType == "string"), "Invalid Event", "error")

	if eventType == "string" then
		Event = {Event :: HookEvent}
	end

	for _, event in pairs(Event) do
		glue_assert(
			table.find(HOOK_EVENTS, event) == nil,
			`Unkown hook event provided '{event}'.\n\t Global hook events: {table.concat(HOOK_EVENTS, ", ")}`
		)
	end

	local hookRef = {
		Id = uuid(),
		callback = fn,
		Event = if typeof(Event) == "string" then {Event} else Event,
	}

	glue_state.hooks[hookRef.Id] = hookRef

	return hookRef.Id
end

local function makeStatic<Interface>(Interface: Interface, UnitConfig: UnitConfig?): Unit<Interface>
	glue_assert(not (glue_state.phase == "idle"), "Cannot register units after glue has started.")

	UnitConfig = (UnitConfig or { Dependencies = {} });  
	(UnitConfig::UnitConfig).Dependencies = (UnitConfig::UnitConfig).Dependencies or {} 

	local UnitId = uuid()

	local unitInterface = Interface :: UnitDefinition<Interface, nil>

	-- Extract hooks & dependencies from the interface to isolate pure interface
	local hooks = {
		onCreate = unitInterface.onCreate,
		onStart = unitInterface.onStart,
	}

	local dependencies = {}

	for _, unit in pairs((UnitConfig :: UnitConfig).Dependencies :: {Unit<any>}) do
		--> units can not depend on dynamic runtimes
		local internal_unit = glue_state.units[unit.UnitId]

		glue_assert(internal_unit.type == glue_state.DYNAMIC_UNIT_ID, "Static Units should not depend on dynamic units.")
		glue_assert(internal_unit.type == glue_state.SPEC_UNIT_ID, "Static Units should not depend on dynamic specs.")

		table.insert(dependencies, unit.UnitId)
	end

	for hook, globalHook in hooks do
		rawset(unitInterface, hook, nil)
	end

	-- Hydrate interface with neccessary components
	rawset(unitInterface, "UnitId", UnitId)

	glue_state.units[UnitId] = {
		id = UnitId,
		hooks = hooks,
		interface = Interface,
		dependencies = dependencies,
		type = glue_state.STATIC_UNIT_ID,
		state = "creating"
	}

	update_dependency_graph()

	run_global_hooks("onDebug", Interface :: any, "StaticUnitRegistered", {
		Traceback = debug.traceback()
	})

	return unitInterface :: any
end

local function makeDynamic<Interface, Props>(Interface: Interface, defaultProps: Props): DynamicUnitSpec<Interface, Props>
	glue_assert(not (glue_state.phase == "idle"), "Cannot register units after glue has started.")
	
	local UnitId = uuid(true)

	local specInterface = Interface :: UnitDefinition<Interface, Props>

	local hooks = {
		onStart = specInterface.onStart,
		onCreate = specInterface.onCreate,
		onDestroy = specInterface.onDestroy
	}

	for hook, globalHook in hooks do
		rawset(specInterface, hook, nil)
	end

	defaultProps = defaultProps or ({} :: any) :: Props

	glue_state.units[UnitId] = {
		id = UnitId,
		hooks = hooks,
		interface = Interface,
		dependencies = {},
		defaultProps = defaultProps,
		type = glue_state.SPEC_UNIT_ID
	}

	run_global_hooks("onDebug", Interface :: any, "DynamicUnitRegistered", {
		UnitId = UnitId,
		Traceback = debug.traceback()
	})

	return {
		UnitId = UnitId,
		interface = (nil :: any) :: Interface,
		defaultProps = (nil :: any) :: Props
	}
end

local function spawnUnit<Interface, Props>(DynamicUnitSpec: DynamicUnitSpec<Interface, Props>)
	glue_assert(glue_state.started == false, `Cannot spawn units when glue is not running.`)

	local dynamic_unit_spec = glue_state.units[DynamicUnitSpec.UnitId]

	glue_assert(dynamic_unit_spec == nil, `Unknown specification provided.`)
	
	-- Probably make this error more verbose
	glue_assert(not (dynamic_unit_spec.type == glue_state.SPEC_UNIT_ID), `Unknown specification provided.`)
	
	return function(Props: Props): DynamicUnit<Interface>
		Props = Props or dynamic_unit_spec.defaultProps

		local function run_hooks(unit, event: HookEvent, ...)
			local hook = rawget(dynamic_unit_spec.hooks, event)
			
			if hook then
				hook(unit, ...)
			end

			run_global_hooks(event, unit)
		end

		run_global_hooks("onDebug", nil, "UnitSpawning", {
			Spec = dynamic_unit_spec.interface,
			SpecId = dynamic_unit_spec.id,
			Traceback = debug.traceback()
		})

		local unit_interface = clone_table_shallow(dynamic_unit_spec.interface);

		unit_interface.UnitId = uuid();
		unit_interface.props = Props
		
		glue_state.units[unit_interface.UnitId] = {
			id = unit_interface.UnitId,
			dependencies = {},
			hooks = {},
			blueprint = dynamic_unit_spec.id,
			type = glue_state.DYNAMIC_UNIT_ID,
			state = "creating"
		}

		run_global_hooks("onDebug", unit_interface, "UnitSpawned", {
			Spec = dynamic_unit_spec.interface,
			SpecId = dynamic_unit_spec.id,
			Traceback = debug.traceback("", 2)
		})

		run_hooks(unit_interface, "onCreate", Props or dynamic_unit_spec.defaultProps)

		set_unit_state(unit_interface.UnitId, "starting")
		
		run_hooks(unit_interface, "onStart");

		set_unit_state(unit_interface.UnitId, "running")

		return unit_interface
	end
end

local function destroyUnit<Interface>(DynamicUnit: DynamicUnit<Interface>)
	local dynamic_unit_internal = glue_state.units[DynamicUnit.UnitId]

	if glue_assert(dynamic_unit_internal == nil, `Unit was not provided`, "warn") then
		return
	end

	glue_assert(not (dynamic_unit_internal.type == glue_state.DYNAMIC_UNIT_ID), `Only dynamic units can be destroyed.`)
	glue_assert(not (get_unit_state(dynamic_unit_internal.id) == "running"), `Attempted to destroy a unit that hasn't been initialized.`)


	set_unit_state(dynamic_unit_internal.id, "destroying")

	run_global_hooks("onDestroy", DynamicUnit)

	glue_state.units[DynamicUnit.UnitId] = nil :: any
	dynamic_unit_internal = nil :: any
	DynamicUnit = nil :: any
end

local function stick()
	run_global_hooks("onDebug", nil, "GlueStickCalled", {
		Traceback = debug.traceback("", 2)
	})

	glue_assert(not (glue_state.phase == "idle"), "Glue.Stick can only be called once")

	local sorted_units = compile_load_order()

	run_lifecycle_hook("onCreate", sorted_units)
	run_lifecycle_hook("onStart", sorted_units)

	run_global_hooks("onDebug", nil, "GlueStickFinished", {
		Traceback = debug.traceback("", 2)
	})

	glue_state.started = true 
end

glue_state.SPEC_UNIT_ID = uuid(true)
glue_state.STATIC_UNIT_ID = uuid(true)
glue_state.DYNAMIC_UNIT_ID = uuid(true)

return table.freeze {
	stick = stick::()->boolean,
	spawnUnit = spawnUnit::<Interface,Props>(DynamicUnitSpec:DynamicUnitSpec<Interface,Props>) -> ((Props) -> DynamicUnit<Interface>),
	destroyUnit = destroyUnit::<Interface>(DynamicUnit:DynamicUnit<Interface>) -> (),
	createHook = createHook::(Event:HookEvent|{HookEvent},Callback:(HookContext)->())->string,
	makeStatic = makeStatic::<Interface>(Interface:Interface,UnitConfig:UnitConfig?)->Unit<Interface>,
	makeDynamic = makeDynamic::<Interface,Props>(Interface:Interface,defaultProps:Props)->DynamicUnitSpec<Interface,Props>
}