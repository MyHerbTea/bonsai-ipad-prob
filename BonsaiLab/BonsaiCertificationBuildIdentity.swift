// Fallback for local developer builds; CI replaces this file before XcodeGen.
enum BonsaiCertificationBuildIdentity {
    static let sourceGitSHA = "unverified-local-build"
    static let workflowRunID = "unverified-local-build"
}
