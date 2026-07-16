// In-progress signup data, held until the user is created on selfie approval.
type Draft = {
  type: "PHONE" | "EMAIL";
  value: string;
  firstName: string;
  lastName: string;
};

const draft: Draft = { type: "PHONE", value: "", firstName: "", lastName: "" };

export function setSignupCredential(type: "PHONE" | "EMAIL", value: string) {
  draft.type = type;
  draft.value = value;
}
export function setSignupName(firstName: string, lastName: string) {
  draft.firstName = firstName;
  draft.lastName = lastName;
}
export function getSignupDraft(): Draft {
  return draft;
}
