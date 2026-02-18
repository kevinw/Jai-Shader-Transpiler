type Elements = {
  jaiInput: HTMLTextAreaElement;
  jaiHighlight: HTMLElement;
  shaderOutput: HTMLElement;
  status: HTMLElement;
  backend: HTMLSelectElement;
  entry: HTMLInputElement;
};

const DEFAULT_JAI = `// Jai shader source
Shader_Params :: struct {
    tint: [3]float;
}

vertex_main :: (vertex_id: s32, params: Shader_Params) -> [4]float {
    x := cast(float)vertex_id * 0.5 - 0.5;
    return .[x, 0.0, 0.0, 1.0];
}
`;

const JAI_KEYWORDS = new Set([
  "if", "else", "for", "while", "switch", "case", "return", "break", "continue", "defer",
  "using", "cast", "enum", "struct", "union", "bit_set", "true", "false", "null", "#import",
  "#load", "#scope_file", "#scope_module", "#scope_export",
]);

const JAI_TYPES = new Set([
  "s8", "s16", "s32", "s64", "u8", "u16", "u32", "u64", "float", "f32", "f64", "bool", "string",
]);

const SHADER_KEYWORDS = new Set([
  "vertex", "fragment", "kernel", "struct", "return", "if", "else", "for", "while", "constexpr",
  "constant", "device", "thread", "threadgroup", "using", "namespace", "float", "float2", "float3",
  "float4", "int", "uint", "void", "half", "sampler", "texture2d",
]);

const SHADER_BUILTINS = new Set([
  "vertex_id", "position", "stage_in", "metal_stdlib",
]);

let compileTimer = 0;
let inFlight: AbortController | null = null;

const els = getElements();
document.body.classList.add("js-enhanced");
els.jaiInput.value = DEFAULT_JAI;
renderJai();
scheduleCompile();

els.jaiInput.addEventListener("input", () => {
  renderJai();
  scheduleCompile();
});

els.jaiInput.addEventListener("scroll", syncJaiScroll);
els.backend.addEventListener("change", scheduleCompile);
els.entry.addEventListener("input", scheduleCompile);

function getElements(): Elements {
  return {
    jaiInput: query("#jaiInput"),
    jaiHighlight: query("#jaiHighlight"),
    shaderOutput: query("#shaderOutput"),
    status: query("#status"),
    backend: query("#backend"),
    entry: query("#entry"),
  };
}

function query<T extends Element>(selector: string): T {
  const node = document.querySelector(selector);
  if (!node) throw new Error(`Missing required element: ${selector}`);
  return node as T;
}

function syncJaiScroll(): void {
  els.jaiHighlight.scrollTop = els.jaiInput.scrollTop;
  els.jaiHighlight.scrollLeft = els.jaiInput.scrollLeft;
}

function renderJai(): void {
  els.jaiHighlight.innerHTML = highlight(els.jaiInput.value, JAI_KEYWORDS, JAI_TYPES, null);
}

function renderOutput(shaderText: string): void {
  els.shaderOutput.innerHTML = highlight(shaderText, SHADER_KEYWORDS, null, SHADER_BUILTINS);
}

function scheduleCompile(): void {
  if (compileTimer) {
    window.clearTimeout(compileTimer);
  }

  compileTimer = window.setTimeout(() => {
    compileTimer = 0;
    void compileShader();
  }, 240);
}

async function compileShader(): Promise<void> {
  if (inFlight) {
    inFlight.abort();
  }

  const ac = new AbortController();
  inFlight = ac;

  setStatus("Compiling...");

  try {
    const body = new URLSearchParams({
      shader: els.jaiInput.value,
      backend: els.backend.value,
      entry: els.entry.value,
    });

    const resp = await fetch("/shader", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
      },
      body: body.toString(),
      signal: ac.signal,
    });

    const text = await resp.text();

    if (!resp.ok) {
      renderOutput(`// error\n${text}`);
      setStatus(`Compile failed (${resp.status})`, true);
      return;
    }

    renderOutput(text);
    setStatus("Compiled.");
  } catch (err) {
    if (ac.signal.aborted) return;
    const message = err instanceof Error ? err.message : String(err);
    renderOutput(`// error\n${message}`);
    setStatus("Compile request failed", true);
  } finally {
    if (inFlight === ac) {
      inFlight = null;
    }
  }
}

function setStatus(message: string, isError = false): void {
  els.status.textContent = message;
  els.status.classList.toggle("error", isError);
}

function escapeHtml(text: string): string {
  return text
    .split("&").join("&amp;")
    .split("<").join("&lt;")
    .split(">").join("&gt;");
}

function highlight(
  input: string,
  keywords: Set<string>,
  types: Set<string> | null,
  builtins: Set<string> | null,
): string {
  const tokenPattern = /\/\/.*|\/\*[\s\S]*?\*\/|"(?:\\.|[^"\\])*"|\b\d+(?:\.\d+)?\b|\b[#A-Za-z_][#A-Za-z0-9_]*\b/g;

  let out = "";
  let cursor = 0;

  for (const match of input.matchAll(tokenPattern)) {
    const i = match.index ?? 0;
    const token = match[0] ?? "";

    if (i > cursor) {
      out += escapeHtml(input.slice(cursor, i));
    }

    out += classifyToken(token, keywords, types, builtins);
    cursor = i + token.length;
  }

  if (cursor < input.length) {
    out += escapeHtml(input.slice(cursor));
  }

  if (out.length === 0) {
    out = " ";
  }

  return out;
}

function classifyToken(
  token: string,
  keywords: Set<string>,
  types: Set<string> | null,
  builtins: Set<string> | null,
): string {
  if (token.startsWith("//") || token.startsWith("/*")) {
    return `<span class="tok-comment">${escapeHtml(token)}</span>`;
  }

  if (token.startsWith("\"")) {
    return `<span class="tok-string">${escapeHtml(token)}</span>`;
  }

  if (/^\d/.test(token)) {
    return `<span class="tok-number">${escapeHtml(token)}</span>`;
  }

  if (keywords.has(token)) {
    return `<span class="tok-keyword">${escapeHtml(token)}</span>`;
  }

  if (types && types.has(token)) {
    return `<span class="tok-type">${escapeHtml(token)}</span>`;
  }

  if (builtins && builtins.has(token)) {
    return `<span class="tok-builtin">${escapeHtml(token)}</span>`;
  }

  return escapeHtml(token);
}
