/// The deployed botvinnik-sync Worker (#203 M1). A single configurable constant
/// so a self-host or provider move later is a one-line change — the payload is
/// one opaque blob under a random id, so migrating is a copy.
const String kSyncEndpoint = 'https://botvinnik-sync.quadrismegistus.workers.dev';
