import { base } from '$app/paths';

// Human commentary from YouTube game reviews (Kaggle chess-reviews-from-youtube),
// looked up by FEN piece placement. The dataset's side-to-move/castling fields are
// CNN-defaulted junk, so only the placement is matched — treat hits as "someone
// discussed this exact position", not "this exact game state".

export interface CommentaryEntry {
	text: string;
	videoUrl: string; // youtube watch URL
	t: number; // seconds into the video
}

interface Db {
	videos: string[];
	positions: Record<string, [string, number, number][]>;
}

let db: Promise<Db | null> | null = null;

async function load(): Promise<Db | null> {
	try {
		const res = await fetch(`${base}/commentary.json`);
		if (!res.ok) return null;
		return (await res.json()) as Db;
	} catch {
		return null; // dataset not built — the panel just stays empty
	}
}

export async function getCommentary(fen: string): Promise<CommentaryEntry[]> {
	db ??= load();
	const d = await db;
	if (!d) return [];
	const rows = d.positions[fen.split(' ')[0]] ?? [];
	return rows.map(([text, vi, t]) => ({ text, videoUrl: d.videos[vi], t }));
}
