// Exact UI strings (default English) — these match the e2e selectors verbatim.
// Keep these labels identical to the Android app so the Appium UiAutomator2
// text()/description() selectors resolve.
export const LANGUAGES = ["ENGLISH", "SWAHILI", "PORTUGUESE"] as const;
export type Language = (typeof LANGUAGES)[number];

export const S = {
  privacyPolicy: "Privacy Policy",
  acceptPrivacyPolicy: "Accept Privacy Policy", // accessibilityLabel
  phone: "PHONE",
  email: "EMAIL",
  phoneHint: "Phone",
  emailHint: "Email",
  firstName: "First Name",
  lastName: "Last Name",
  track: "TRACK",
  upload: "UPLOAD",
  messages: "MESSAGES",
  organization: "Organization",
  organizationHint: "Organization (optional)",
  note: "NOTE",
  addNoteToTree: "Add note to tree",
  uploadTreesSoon: "Upload Trees Soon",
  ok: "OK",
  // accessibilityLabels (-> Android content-desc)
  navigateForward: "Navigate forward",
  navigateBack: "Navigate back",
  takeSelfie: "Take selfie",
  approveSelfie: "Approve selfie",
  takeTreePhoto: "Take tree photo",
  approveTree: "Approve tree",
  rejectTree: "Reject tree",
  saveNote: "Save note",
  dismissTutorial: "Dismiss tutorial",
  treesReadyToUpload: "Trees ready to upload",
  treesUploaded: "Trees uploaded",
} as const;
