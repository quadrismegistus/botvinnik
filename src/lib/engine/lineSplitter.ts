// UCI pipes deliver chunks, not lines — buffer and split defensively.
// Used by the native transport; unit-tested without any Tauri runtime.
export function createLineSplitter(onLine: (line: string) => void): (chunk: string) => void {
	let buffer = '';
	return (chunk: string) => {
		buffer += chunk;
		const lines = buffer.split('\n');
		buffer = lines.pop() ?? '';
		for (const line of lines) {
			const trimmed = line.replace(/\r$/, '');
			if (trimmed) onLine(trimmed);
		}
	};
}
