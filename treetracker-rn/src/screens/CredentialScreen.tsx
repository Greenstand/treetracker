import React, { useState } from "react";
import { Pressable, StyleSheet, Text, TextInput, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { S } from "../strings";
import { Nav } from "../navigation";
import { setSignupCredential } from "../signupDraft";

// Privacy policy + credential (PHONE/EMAIL) entry. Mirrors CredentialEntryView.
export default function CredentialScreen() {
  const nav = useNavigation<Nav<"Credential">>();
  const [accepted, setAccepted] = useState(false);
  const [type, setType] = useState<"PHONE" | "EMAIL">("PHONE");
  const [value, setValue] = useState("");

  const valid =
    type === "PHONE"
      ? value.replace(/\D/g, "").length >= 7
      : value.includes("@");

  return (
    <View style={styles.root}>
      <View style={styles.body}>
        <Text style={styles.title}>{S.privacyPolicy}</Text>
        <Pressable
          accessibilityLabel={S.acceptPrivacyPolicy}
          accessibilityRole="checkbox"
          accessibilityState={{ checked: accepted }}
          onPress={() => setAccepted((a) => !a)}
          style={styles.accept}>
          <Text style={styles.acceptText}>
            {accepted ? "☑" : "☐"}  I accept the Privacy Policy
          </Text>
        </Pressable>

        <View style={styles.toggleRow}>
          <Pressable
            onPress={() => setType("PHONE")}
            style={[styles.toggle, type === "PHONE" && styles.toggleSel]}>
            <Text style={styles.toggleText}>{S.phone}</Text>
          </Pressable>
          <Pressable
            onPress={() => setType("EMAIL")}
            style={[styles.toggle, type === "EMAIL" && styles.toggleSel]}>
            <Text style={styles.toggleText}>{S.email}</Text>
          </Pressable>
        </View>

        <TextInput
          style={styles.input}
          placeholder={type === "PHONE" ? S.phoneHint : S.emailHint}
          keyboardType={type === "PHONE" ? "phone-pad" : "email-address"}
          autoCapitalize="none"
          value={value}
          onChangeText={setValue}
        />
      </View>
      <ActionBar
        onBack={() => nav.goBack()}
        forwardEnabled={accepted && valid}
        onForward={() => {
          setSignupCredential(type, value);
          nav.navigate("Name");
        }}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#fff" },
  body: { flex: 1, padding: 24, paddingTop: 60, gap: 20 },
  title: { fontSize: 22, fontWeight: "700", color: "#1B5E20" },
  accept: { paddingVertical: 8 },
  acceptText: { fontSize: 16 },
  toggleRow: { flexDirection: "row", gap: 12 },
  toggle: {
    flex: 1,
    paddingVertical: 14,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: "#2E7D32",
    alignItems: "center",
  },
  toggleSel: { backgroundColor: "#C8E6C9" },
  toggleText: { fontSize: 18, fontWeight: "600", color: "#1B5E20" },
  input: {
    borderWidth: 1,
    borderColor: "#999",
    borderRadius: 8,
    padding: 14,
    fontSize: 16,
  },
});
