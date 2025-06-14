// typings for the PI helper injected by Stream Deck
declare function connectElgatoStreamDeckPropertyInspector(
  inPort: number,
  inUUID: string,
  inRegisterEvent: string,
  inInfo: string,
  inActionInfo: string
): PropertyInspector;

interface PropertyInspector {
  setSettings(settings: Record<string, unknown>): void;
}

// your light data model
interface Light {
  id: string;
  name: string;
}

// connect to the Stream Deck Property Inspector
const sdpi = connectElgatoStreamDeckPropertyInspector(
  inPort, inUUID, inRegisterEvent, inInfo, inActionInfo
);

// --- MOCK: replace with real IPC/HTTP/domain-socket call ---
async function getLights(): Promise<Light[]> {
  return Promise.resolve([
    { id: '1', name: 'Front' },
    { id: '2', name: 'Back' },
    { id: '3', name: 'Side' }
  ]);
}

async function buildUI(): Promise<void> {
  const lights = await getLights();
  const container = document.getElementById('lightsContainer')!;
  container.innerHTML = ''; // clear “Loading…”

  lights.forEach(light => {
    const row = document.createElement('div');
    row.className = 'light';

    const label = document.createElement('span');
    label.textContent = light.name;
    row.appendChild(label);

    (['On', 'Off'] as const).forEach(cmd => {
      const btn = document.createElement('button');
      btn.textContent = cmd;
      btn.addEventListener('click', () => {
        sdpi.setSettings({
          lightId: light.id,
          command: cmd.toLowerCase()
        });
      });
      row.appendChild(btn);
    });

    container.appendChild(row);
  });
}

document.addEventListener('DOMContentLoaded', () => {
  buildUI().catch(console.error);
});

