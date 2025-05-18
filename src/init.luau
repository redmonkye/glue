--[[
	
    The entry point of Glue.

    https://github.com/redmonkye/glue

]]

export type Provider<Interface> = Interface & {
	ProviderId: string
}

export type ProviderDefinition =  {
    Hooks: {}?,
	Dependencies: {Provider<any>}?,
	[any]: any
}

type LifecycleHooks<Interface> = {
	onCreate: (Interface) -> ()?,
	onStart: (Interface) -> ()?,
}

type ProviderInternal<T> = {
	id: string,
	interface: T,
	dependencies: {string},
	hooks: LifecycleHooks<T>
}

local glue_state = {
	hooks = {} :: {HookRef},
	providers = {},
	hook_dependants = {},
	dependency_graph = {},
}

local function uuid()
	local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function (c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

local function unpack_provider_ids(list: {Provider<any>})
	local unpacked = {}

	for _, provider in list do
		table.insert(unpacked, provider.ProviderId)
	end

	return unpacked
end

local function compile_directed_graph(providers: { ProviderInternal<any> })
	local directed_graph = {}

	for _, provider in providers do
		directed_graph[provider.id] = provider.dependencies
	end

	return directed_graph
end
    
local function determine_provider_order(directed_graph: {[string]: {string}})
	local sorted_providers = {}

	local n = 0
	local queue = {}
	local in_degrees = {}
	
	for node in directed_graph do
		n += 1
		in_degrees[node] = 0
	end

	-- empty graph
	if n == 0 then
		return {}
	end

	for _, edges in directed_graph do
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
		local node = table.remove(queue)

		table.insert(sorted_providers, 1, node)

		for _, edge in directed_graph[node] do
			in_degrees[edge] -= 1
			if in_degrees[edge] == 0 then
				table.insert(queue, 1, edge)
			end
		end
	until #queue == 0

	return sorted_providers
end

function Provider<T>(Interface: T & ProviderDefinition & LifecycleHooks<T>): Provider<T>
	local providerId = uuid()

	-- Extract hooks & dependencies from the interface to isolate pure interface
	local hooks = {
		onCreate = Interface.onCreate,
		onStart = Interface.onStart,
		onTick = Interface.onTick,
		onRender = Interface.onRender,

		table.unpack(Interface.Hooks or {})
	}

	local dependencies = unpack_provider_ids(Interface.Dependencies or {})

	Interface.Hooks = nil
	Interface.Dependencies = nil

	for hook, globalHook in hooks do
		rawset(Interface, hook, nil)
	end

	-- Hydrate interface with neccessary components
	Interface.ProviderId = providerId

	glue_state.providers[providerId] = {
		id = providerId,
		hooks = hooks,
		interface = Interface,
		dependencies = dependencies
	}

	glue_state.dependency_graph = compile_directed_graph(glue_state.providers)

	return Interface
end

export type HookEvent = 
	"onCreate" 
	| "onStart"

export type HookContext = {
	Event: HookEvent,
	Providers: {Provider<any>},
}

type HookRef = {
	Id: string,
	hookFn: (HookContext) -> (),
	Event: { HookEvent },
}

local function run_lifecycle_hook(event: HookEvent, sorted_providers: { string }, hook_dependants_graphs: { [string]: {string} }, ...)
	for _, providerId in sorted_providers do
		local provider = glue_state.providers[providerId]
		
		if provider.hooks[event] == nil then
			continue
		end

		provider.hooks[event](provider.interface, ...)
	end

	for id, hookRef: HookRef in glue_state.hooks do
		if table.find(hookRef.Event, event ) then
			-- cached dependants list to avoid recomputation
			if glue_state.hook_dependants[hookRef.Id] == nil then

				glue_state.hook_dependants[hookRef.Id] = {}

				for _, providerId in hook_dependants_graphs[id] do
					table.insert(glue_state.hook_dependants[hookRef.Id], glue_state.providers[providerId].interface)				
				end
			end

			hookRef.hookFn({
				Event = event,
				Providers = glue_state.hook_dependants[hookRef.Id]
			}, ...)
		end
	end
end

function Hook<T>(Event: HookEvent | { HookEvent }, fn: (HookContext, ...any) -> ()): string
	local hookRef = {
		Id = uuid(),
		hookFn = fn,
		Event = if typeof(Event) == "string" then {Event} else Event
	}

	glue_state.hooks[hookRef.Id] = hookRef

	return hookRef.Id
end

function Stick()
	local sorted_providers = determine_provider_order(glue_state.dependency_graph)

	local hook_dependants_graphs = {}

	for id,  hookRef: HookRef in glue_state.hooks do
		hook_dependants_graphs[id] = {}
	end

	for _, provider in glue_state.providers do
		for _, hookId: HookRef in ipairs(provider.hooks) do
			table.insert(hook_dependants_graphs[hookId], provider.id)
		end
	end

	run_lifecycle_hook("onCreate", sorted_providers, hook_dependants_graphs)
	run_lifecycle_hook("onStart", sorted_providers, hook_dependants_graphs)
end

return {
	Hook = Hook,
	Stick = Stick,
	Provider = Provider
}