protocol AppleSignInCredentialStoring: AnyObject {
    func load() -> AppleSignInCredential?
    func save(_ credential: AppleSignInCredential)
    func clear()
}
