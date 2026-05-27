import NexusDomain

func structuredInterruptedSessionFailureMessage(for providerID: ProviderID) -> String {
    "\(providerID.displayName) Session Record survived, but its live runtime was lost when the background service restarted. Relaunch to create a new live runtime."
}
