---
sidebar_position: 9
---

# VSC Snippets

Here are some VSCode snippets.

## Glue

```lua
local Glue = require(game:GetService('ReplicatedStorage').Packages.Glue)
```

```json
"Glue": {
	"prefix": "glue",
	"body": "local Glue = require(game:GetService('ReplicatedStorage').Packages.Glue)",
    "description": "Require Glue."
}
```


## Provider

```lua
local Provider = Glue.Provider("Provider")

function Provider:onCreate()

end

function Provider:onStart()

end

return Provider
```

```json
"Provider":{
    "prefix": "provider",
    "body": [
        "local ${0:$TM_FILENAME_BASE} = Glue.Provider('${0:$TM_FILENAME_BASE}')\n\n",
        "function ${0:$TM_FILENAME_BASE}:onCreate()\n\t\nend\n\n",
        "function ${0:$TM_FILENAME_BASE}:onStart()\n\t\nend\n\n",
        "return ${0:$TM_FILENAME_BASE}"
    ],
    "description": "Create a Provider."
}
```