# ADR 0033: Some remote structured Sessions may be ready without a continuously attached live runtime

## Status
Accepted

Nexus now needs remote structured **Sessions** such as IBM Bob whose provider-native continuity resumes on demand rather than through a continuously attached remote runtime, so some remote structured **Sessions** may stay **ready** and inspectable from persisted history and stored provider-native continuity even while no live remote runtime is attached. **Remote Session Strategy** still applies, but only while remote runtime work is active; this preserves one product meaning of **ready** across local and remote on-demand structured **Sessions** and avoids coupling remote readiness to continuous process liveness.
