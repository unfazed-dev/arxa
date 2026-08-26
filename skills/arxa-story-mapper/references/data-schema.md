# Input JSON schema and field reference

```json
{
  "project": "E-Commerce Platform MVP",
  "releases": [
    {"name": "Release 1", "description": "MVP core features"},
    {"name": "Release 2", "description": "UX improvements"},
    {"name": "Release 3", "description": "Growth features"}
  ],
  "epics": [
    {
      "name": "User System",
      "features": [
        {
          "name": "Registration & Login",
          "stories": [
            {
              "name": "Phone number signup",
              "priority": "must",
              "release": "Release 1",
              "points": 3,
              "description": "User can register with phone number and verification code"
            },
            {
              "name": "WeChat login",
              "priority": "should",
              "release": "Release 2",
              "points": 5
            }
          ]
        }
      ]
    }
  ]
}
```

#### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `project` | string | ✅ | Project name |
| `releases` | array | ✅ | Release list (in order) |
| `releases[].name` | string | ✅ | Version name — must match the `release` field in Stories |
| `releases[].description` | string | ❌ | Version description |
| `epics` | array | ✅ | Epic list |
| `epics[].name` | string | ✅ | Epic name |
| `epics[].features` | array | ✅ | Feature list |
| `epics[].features[].name` | string | ✅ | Feature name |
| `epics[].features[].stories` | array | ✅ | Story list |
| `stories[].name` | string | ✅ | Story name |
| `stories[].priority` | string | ✅ | must / should / could / wont |
| `stories[].release` | string | ✅ | Assigned version name |
| `stories[].points` | number | ❌ | Story Points |
| `stories[].description` | string | ❌ | Additional description |

