// Lightweight persisted store (AsyncStorage) with a subscribe API, backing the
// onboarding + capture + upload flows. clearApp() (Appium fresh launch) wipes
// AsyncStorage, so a fresh start has no user -> onboarding shows.
import AsyncStorage from "@react-native-async-storage/async-storage";
import { useEffect, useState } from "react";

export type User = {
  uuid: string;
  firstName: string;
  lastName: string;
  phone?: string;
  email?: string;
  photoPath?: string;
  wallet: string;
};

export type Capture = {
  id: string;
  sessionId: string;
  lat: number;
  lon: number;
  note: string;
  photoPath: string;
  capturedAt: string; // ISO
  absStepCount: number;
  deltaStepCount: number;
  uploaded: boolean;
  imageUrl?: string;
};

export type Session = {
  id: string;
  organization: string;
  originUserId: string;
  targetWallet: string;
};

type State = {
  users: User[];
  sessions: Session[];
  captures: Capture[];
  uploadedCount: number;
};

const KEY = "treetracker-rn-state-v1";
let state: State = { users: [], sessions: [], captures: [], uploadedCount: 0 };
let loaded = false;
const listeners = new Set<() => void>();

function emit() {
  listeners.forEach((l) => l());
}
async function persist() {
  await AsyncStorage.setItem(KEY, JSON.stringify(state));
}

export async function loadState(): Promise<void> {
  if (loaded) return;
  try {
    const raw = await AsyncStorage.getItem(KEY);
    if (raw) state = JSON.parse(raw);
  } catch {
    /* corrupt/missing -> defaults */
  }
  loaded = true;
  emit();
}

export function getState(): State {
  return state;
}
export function readyToUpload(): number {
  return state.captures.filter((c) => !c.uploaded).length;
}
export function uploadedCount(): number {
  return state.uploadedCount;
}

export async function addUser(u: User): Promise<void> {
  state.users = [...state.users, u];
  await persist();
  emit();
}
export async function addSession(s: Session): Promise<void> {
  state.sessions = [...state.sessions, s];
  await persist();
  emit();
}
export async function addCapture(c: Capture): Promise<void> {
  state.captures = [...state.captures, c];
  await persist();
  emit();
}
export async function markAllUploaded(urls: Record<string, string>): Promise<void> {
  let n = 0;
  state.captures = state.captures.map((c) => {
    if (!c.uploaded) {
      n += 1;
      return { ...c, uploaded: true, imageUrl: urls[c.id] ?? c.imageUrl };
    }
    return c;
  });
  state.uploadedCount += n;
  await persist();
  emit();
}

export function subscribe(fn: () => void): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

// React hook to re-render on store changes.
export function useStore<T>(selector: (s: State) => T): T {
  const [, force] = useState(0);
  useEffect(() => subscribe(() => force((n) => n + 1)), []);
  return selector(state);
}
