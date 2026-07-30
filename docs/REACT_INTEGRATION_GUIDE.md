# Integrating React into a Phoenix LiveView App

A step-by-step guide to adding React components to a Phoenix 1.7+/1.8 app that uses the default esbuild setup. This is the playbook used in production by the `testy` project.

## Prerequisites

- A Phoenix 1.7+ or 1.8 app with the default esbuild setup
- Node.js **≥ 20** installed (for npm)
- A LiveView-based frontend (the React integration mounts through LiveView hooks)

---

## Step 1: Add a `package.json` to `assets/`

If your Phoenix project doesn't already have a `package.json` in `assets/`, create one:

```shell
cd assets
npm init -y
```

Edit it to:

```json
{
  "name": "my-app-assets",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1"
  }
}
```

---

## Step 2: Install React and Your React Libraries

From `assets/`:

```shell
cd assets
npm install react react-dom
```

Additional libraries (e.g. a rich text editor):

```shell
npm install @tiptap/react @tiptap/starter-kit @heroicons/react @radix-ui/react-tooltip
```

This creates `assets/node_modules/` and `assets/package-lock.json`.

**Commit `package-lock.json`** — it pins transitive dependency versions so CI and other devs get the exact same tree. Add `assets/node_modules` to `.gitignore`.

---

## Step 3: Configure esbuild for JSX

In `config/config.exs`, update your esbuild config. The critical flags:

- `--jsx=automatic` — React 17+ JSX transform (no `import React` required)
- `--format=esm` + `--splitting` — enables code splitting so React is loaded on-demand

```elixir
config :esbuild,
  version: "0.25.4",
  my_app: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --format=esm --splitting --chunk-names=chunks/[name]-[hash] --jsx=automatic --define:process.env.NODE_ENV=\"production\" --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]
```

Replace `my_app` with your actual app name.

### Key flags explained

| Flag | Purpose |
| ---- | ------- |
| `--jsx=automatic` | React 17+ JSX transform — no `import React` needed in `.jsx` files |
| `--format=esm` | Output ES modules (required for `--splitting`) |
| `--splitting` | Enables code splitting — React is lazy-loaded only when needed |
| `--chunk-names=chunks/[name]-[hash]` | Names code-split chunks for caching |
| `--define:process.env.NODE_ENV=\"production\"` | Tells React to use its production build |
| `--target=es2022` | Target modern browsers |

---

## Step 4: Override esbuild Config for Development

In `config/dev.exs`, override `NODE_ENV` so React loads its development build (better error messages, warnings):

```elixir
config :esbuild, :my_app,
  args:
    ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --format=esm --splitting --chunk-names=chunks/[name]-[hash] --jsx=automatic --define:process.env.NODE_ENV=\"development\" --external:/fonts/* --external:/images/* --alias:@=.),
  cd: Path.expand("../assets", __DIR__),
  env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
```

The only difference is `\"development\"` vs `\"production\"`.

---

## Step 5: Add JSX File Watching for Live Reload

In `config/dev.exs`, add `.jsx` to the `live_reload` patterns:

```elixir
live_reload: [
  web_console_logger: true,
  patterns: [
    ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
    ~r"priv/gettext/.*(po)$",
    ~r"lib/my_app_web/(?:controllers|live|components|router)/?.*\.(ex|heex)$",
    ~r"assets/js/.*(jsx|js|css)$"
  ]
]
```

The final pattern is the one you add.

---

## Step 6: Link the React-generated CSS Bundle

With `--splitting` and CSS imports in hooks, esbuild outputs a **separate** CSS file alongside `app.css` (e.g. `priv/static/assets/js/app.css`). If you import any CSS from a hook or component, you **must** add a second `<link>` tag in your root layout, otherwise the styles won't load.

In `lib/my_app_web/components/layouts/root.html.heex`:

```heex
<link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
<link phx-track-static rel="stylesheet" href={~p"/assets/js/app.css"} />
```

Skip this step if you plan to use Tailwind classes exclusively for React styling (Step 11, Option B).

---

## Step 7: Create a React Component

React components go under `assets/js/react/`. Example — a read-only rich text preview that receives JSON content via props:

```jsx
// assets/js/react/RichTextPreview.jsx
import { useMemo } from "react";

export default function RichTextPreview({ content }) {
  const parsed = useMemo(() => {
    try {
      return typeof content === "string" ? JSON.parse(content) : content;
    } catch {
      return null;
    }
  }, [content]);

  if (!parsed) {
    return <div className="text-sm text-gray-500">No content</div>;
  }

  return (
    <div className="prose">
      {parsed.blocks?.map((block, i) => (
        <p key={i}>{block.text}</p>
      ))}
    </div>
  );
}
```

**Note:** With `--jsx=automatic`, do NOT `import React from "react"`. Import only specific hooks (`useState`, `useEffect`, `useMemo`, …).

---

## Step 8: Create a LiveView Hook That Mounts React

Hook files live under `assets/js/hooks/`. Use the `.jsx` extension — the file contains JSX:

```jsx
// assets/js/hooks/rich_text_preview_hook.jsx
export const RichTextPreview = {
  async mounted() {
    // Lazy-load React and the component (code splitting!)
    const [ReactDOMClient, { default: RichTextPreview }] = await Promise.all([
      import("react-dom/client"),
      import("../react/RichTextPreview"),
    ]);

    // CJS interop — createRoot may live on `.default`
    const createRoot =
      ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;

    // Read data attributes passed from the LiveView
    const { content } = this.el.dataset;

    this.root = createRoot(this.el);
    this.root.render(<RichTextPreview content={content} />);
  },

  destroyed() {
    // Guard against double-unmount: React throws if unmount is called twice
    if (this.root) {
      this.root.unmount();
      this.root = null;
    }
  },
};
```

### Why dynamic imports?

`import("react-dom/client")` instead of a top-level `import` means React is downloaded only when the hook mounts. Pages that don't use React never load it. This leverages esbuild's `--splitting` flag.

### The CJS interop workaround

esbuild bundles `react-dom/client` as CommonJS. The named `createRoot` export may live on the module itself or under `.default`. The pattern `ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot` handles both.

---

## Step 9: Register the Hook in `app.js`

In `assets/js/app.js`:

```js
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";

// Import your React hook (extension omitted — esbuild resolves .jsx automatically)
import { RichTextPreview } from "./hooks/rich_text_preview_hook";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: {
    // The key here must EXACTLY match phx-hook="..." in your template
    RichTextPreview,
  },
});
```

The import path omits the `.jsx` extension — esbuild resolves it automatically. Include it (`./hooks/rich_text_preview_hook.jsx`) if you prefer to be explicit; both work.

---

## Step 10: Use the Hook in a LiveView

Your LiveView renders a `<div>` with three critical attributes:

1. **`id`** — unique DOM ID (LiveView requires this for hooks)
2. **`phx-hook="RichTextPreview"`** — connects the element to the JS hook
3. **`phx-update="ignore"`** — tells LiveView never to patch this subtree

```elixir
defmodule MyAppWeb.ContentLive do
  use MyAppWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="p-8">
        <h1 class="text-2xl font-bold mb-4">Content Preview</h1>

        <div
          id="content-preview"
          phx-hook="RichTextPreview"
          phx-update="ignore"
          data-content={Jason.encode!(@content)}
          class="min-h-16"
        >
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :content, %{blocks: [%{text: "Hello from React"}]})}
  end
end
```

### How data flows from LiveView to React

- **`data-*` attributes** on the `<div>` are read in the hook via `this.el.dataset`.
- `data-user-id="42"` → `this.el.dataset.userId` (automatic camelCase).
- For complex data, JSON-encode: `data-content={Jason.encode!(@content)}`, then parse in the hook or component with `JSON.parse(...)`.

---

## Step 11: CSS for React Components

### Option A — Dedicated CSS file imported in the hook

Create a CSS file next to your component, then import it at the top of the hook:

```css
/* assets/js/react/rich_text_preview.css */
.rtp {
  --text: #6b6375;
  --bg: #fff;
  border: 1px solid #e5e4e7;
  border-radius: 8px;
  background: var(--bg);
}
```

```jsx
// assets/js/hooks/rich_text_preview_hook.jsx
import "../react/rich_text_preview.css";
// ... rest of hook
```

esbuild bundles this into `priv/static/assets/js/app.css` — see **Step 6** for the root layout `<link>` tag you need.

### Option B — Tailwind classes directly in JSX

With Tailwind v4, add `@source "../js";` so it scans `.jsx` files for class names:

```css
/* assets/css/app.css */
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
```

This project uses both: Tailwind for layout and dedicated CSS for complex widgets like editors.

---

## Step 12: (Optional) Create a JSON API for Data Fetching

For React components that fetch or mutate data, create dedicated JSON endpoints instead of round-tripping through the LiveView socket.

### Client-side: API utility module

```js
// assets/js/react/api.js
function getCSRFToken() {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.getAttribute("content") : "";
}

async function request(url, options = {}) {
  const headers = {
    "Content-Type": "application/json",
    Accept: "application/json",
    "x-csrf-token": getCSRFToken(),
    ...options.headers,
  };

  const response = await fetch(url, { ...options, headers });

  if (!response.ok) {
    const errorBody = await response.text();
    let message;
    try {
      const parsed = JSON.parse(errorBody);
      message = parsed.error || parsed.message || response.statusText;
    } catch {
      message = response.statusText;
    }
    throw new Error(message);
  }

  return response.json();
}

export function fetchItem(id) {
  return request(`/api/items/${id}`);
}

export function saveItem(id, data) {
  return request(`/api/items/${id}`, {
    method: "POST",
    body: JSON.stringify(data),
  });
}
```

### Server-side: API pipeline and controller

```elixir
pipeline :my_api do
  plug :accepts, ["json"]
  plug :fetch_session
  plug :protect_from_forgery
  # Add auth plugs as needed
end

scope "/api", MyAppWeb do
  pipe_through :my_api

  get "/items/:id", ItemApiController, :show
  post "/items/:id", ItemApiController, :save
end
```

```elixir
defmodule MyAppWeb.ItemApiController do
  use MyAppWeb, :controller
  alias MyApp.Items

  def show(conn, %{"id" => id}) do
    item = Items.get_item!(id)
    json(conn, %{item: item})
  end

  def save(conn, %{"id" => id} = params) do
    item = Items.get_item!(id)

    case Items.update_item(item, params) do
      {:ok, _updated} ->
        json(conn, %{ok: true, saved_at: DateTime.utc_now()})

      {:error, _changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed"})
    end
  end end
```

### CSRF model choice

Using `:protect_from_forgery` in a JSON pipeline is a deliberate choice: it couples API auth to the Phoenix session cookie, which is exactly what you want when the React component is rendered on an authenticated LiveView page. The client sends the CSRF token via the `x-csrf-token` header (read from the `<meta>` tag).

If you need a token-authenticated API for external clients (mobile, third parties), that's a separate pipeline — don't mix the two.

---

## Step 13: Production Build

`mix assets.deploy` runs the production esbuild config and the Phoenix cache-digest step. `--splitting` writes chunks to `priv/static/assets/js/chunks/` — these are digested and served correctly as long as your static plug is configured the default way. Verify after your first deploy:

```shell
mix assets.deploy
ls priv/static/assets/js/chunks/
```

You should see hashed filenames like `react-dom_client-X7Y2AB4F.js`. Serve them from the same `/assets/js/` path you already use; no extra config is needed.

---

## Communication Between React and LiveView

### LiveView → React (initial data)

`data-*` attributes on the hook element. Covered in Step 10.

### React → Server (API calls)

Standard `fetch()` to your JSON endpoints with the CSRF token. Covered in Step 12.

### React → LiveView (push events) — Advanced

To send events back to the LiveView (e.g. to trigger navigation or flash messages):

```jsx
mounted() {
  // ... mount React ...
  // Expose a bound callback that React components can call
  this.el.pushToLiveView = (event, payload) => {
    this.pushEvent(event, payload);
  };
}
```

Store the callback on `this.el` (not `window`) so it's scoped to the element and doesn't leak globally.

### LiveView → React (updates after mount) — Advanced

For LiveView-driven updates after the initial mount, use `handleEvent`:

```jsx
mounted() {
  // ... mount React ...
  this.handleEvent("update-content", ({ content }) => {
    // Re-render with new props — React reconciles; internal state persists
    this.root.render(<RichTextPreview content={content} />);
  });
}
```

Note that calling `this.root.render(...)` again **reconciles** rather than remounts. Component state and refs persist across re-renders, which is usually what you want. If you need a fresh instance, change the root component's `key` prop.

---

## Key Patterns and Conventions

### 1. Always use `phx-update="ignore"`

The single most important rule. Without it, LiveView patches the DOM that React is managing and crashes.

### 2. Always unmount on `destroyed()` — with a guard

```jsx
destroyed() {
  if (this.root) {
    this.root.unmount();
    this.root = null;
  }
}
```

Prevents memory leaks on navigation and guards against double-unmount.

### 3. Lazy-load React with dynamic imports

```jsx
const [ReactDOMClient, { default: MyComponent }] = await Promise.all([
  import("react-dom/client"),
  import("../react/MyComponent"),
]);
```

Pages that don't use React never load it.

### 4. Pass data via `data-*` attributes

- Simple values: `data-user-id={@user.id}` → `this.el.dataset.userId`
- Complex data: `data-config={Jason.encode!(@config)}` → parse with `JSON.parse(...)`

### 5. Separate JSON APIs for data fetching

React components fetch their own data from JSON endpoints rather than bidirectionally through the LiveView socket. Keeps both sides simpler.

### 6. File layout

- Hooks → `assets/js/hooks/` (`.jsx` since they contain JSX)
- Components → `assets/js/react/`
- Shared utilities (`api.js`, `*.css`) → `assets/js/react/`

---

## Project File Structure

```
assets/
├── css/
│   └── app.css                       # Main CSS (Tailwind)
├── js/
│   ├── app.js                        # Entry point — registers hooks
│   ├── hooks/
│   │   └── rich_text_preview_hook.jsx
│   └── react/
│       ├── api.js                    # fetch + CSRF utility
│       ├── rich_text_preview.css     # Component-scoped CSS
│       └── RichTextPreview.jsx
├── package.json
├── package-lock.json                 # Commit this
└── node_modules/                     # .gitignore this

lib/my_app_web/
├── live/
│   └── content_live.ex               # LiveView → RichTextPreview hook
└── controllers/
    └── item_api_controller.ex        # JSON API
```

---

## Troubleshooting

### `createRoot is not a function`

CJS interop. Always use:

```js
const createRoot =
  ReactDOMClient.createRoot ?? ReactDOMClient.default?.createRoot;
```

### React component does not render

1. Check the browser console.
2. Verify the `phx-hook="..."` name matches the key in `app.js`'s `hooks` object.
3. Ensure the `<div>` has a unique `id`.
4. Ensure `phx-update="ignore"` is set.

### LiveView keeps resetting the React component

Missing `phx-update="ignore"`. Every LiveView re-render wipes the React DOM tree without it.

### CSS from React components not loading

Make sure you linked `priv/static/assets/js/app.css` in your root layout (Step 6).

### Tailwind classes not working in React components

Ensure `app.css` has `@source "../js";` so Tailwind v4 scans your JSX files.

### Hot reload not working for JSX files

Add `~r"assets/js/.*(jsx|js|css)$"` to `live_reload` patterns in `config/dev.exs`.

### CSRF token errors on API calls

Ensure your API pipeline has `:fetch_session` and `:protect_from_forgery`, and the JS utility sends `x-csrf-token` from the `<meta>` tag.

### Chunks 404 in production

Confirm `priv/static/assets/js/chunks/` is deployed. Some deploy pipelines aggressively prune what they consider "non-entrypoint" files — the chunked modules must ship.

---

## Summary Checklist

- [ ] Create `assets/package.json`; install `react` + `react-dom`
- [ ] Add `--jsx=automatic`, `--format=esm`, `--splitting` to esbuild config in `config/config.exs`
- [ ] Set `--define:process.env.NODE_ENV` to `"development"` in `dev.exs`, `"production"` in `config.exs`
- [ ] Add `~r"assets/js/.*(jsx|js|css)$"` to live reload patterns in `dev.exs`
- [ ] Add `<link>` for `priv/static/assets/js/app.css` in root layout (if importing CSS from hooks)
- [ ] Create React components in `assets/js/react/`
- [ ] Create LiveView hooks in `assets/js/hooks/` (`.jsx` files)
- [ ] Register hooks in `app.js`'s LiveSocket `hooks` object
- [ ] Use `phx-hook`, `phx-update="ignore"`, unique `id`, and `data-*` attributes in templates
- [ ] (Optional) Create JSON API endpoints + controller for data fetching
- [ ] Add `assets/node_modules` to `.gitignore`; commit `package-lock.json`
- [ ] Verify `mix assets.deploy` produces `priv/static/assets/js/chunks/`
