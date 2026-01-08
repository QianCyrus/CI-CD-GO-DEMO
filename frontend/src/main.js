import "./style.css";

const form = document.querySelector("#form");
const nameInput = document.querySelector("#name");
const out = document.querySelector("#out");

async function callHello(name) {
  const url = `/api/v1/hello?name=${encodeURIComponent(name)}`;
  const resp = await fetch(url);
  const json = await resp.json();
  if (!resp.ok) {
    throw new Error(json?.error ?? `HTTP ${resp.status}`);
  }
  return json;
}

function pretty(obj) {
  return JSON.stringify(obj, null, 2);
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  out.textContent = "loading...";

  try {
    const json = await callHello(nameInput.value);
    out.textContent = pretty(json);
  } catch (err) {
    out.textContent = `error: ${err?.message ?? String(err)}`;
  }
});

