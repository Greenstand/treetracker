import React, { useState } from "react";
import { ScrollView, StyleSheet, Text, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { Screen, TopBar } from "../components/Layout";
import {
  ApprovalButton,
  DepthButton,
  DepthTextButton,
} from "../components/DepthButton";
import { BorderedTextField } from "../components/BorderedTextField";
import { AppColors, ButtonColors, Fonts, TextColors } from "../theme";
import { S } from "../strings";
import { Nav } from "../navigation";
import { setSignupCredential } from "../signupDraft";

// Privacy policy dialog (on entry) + credential (PHONE/EMAIL) entry.
// Mirrors Android CredentialEntryView.
export default function CredentialScreen() {
  const nav = useNavigation<Nav<"Credential">>();
  const [showPrivacy, setShowPrivacy] = useState(true);
  const [type, setType] = useState<"PHONE" | "EMAIL">("PHONE");
  const [value, setValue] = useState("");

  const valid =
    type === "PHONE"
      ? value.replace(/\D/g, "").length >= 7
      : value.includes("@");

  // Language button on the right of the top bar (matches Android).
  const langButton = (
    <DepthTextButton
      label="ENGLISH"
      width={120}
      height={50}
      onPress={() => nav.navigate("Language")}
    />
  );

  return (
    <Screen>
      <TopBar right={langButton} />

      <View style={styles.body}>
        <View style={styles.toggleRow}>
          <DepthButton
            colors={ButtonColors.ProgressGreen}
            width={120}
            height={50}
            style={{ marginRight: 12 }}
            onPress={() => setType("PHONE")}>
            <Text style={styles.toggleText}>{S.phone}</Text>
          </DepthButton>
          <DepthButton
            colors={ButtonColors.ProgressGreen}
            width={120}
            height={50}
            onPress={() => setType("EMAIL")}>
            <Text style={styles.toggleText}>{S.email}</Text>
          </DepthButton>
        </View>

        <BorderedTextField
          style={styles.input}
          placeholder={type === "PHONE" ? S.phoneHint : S.emailHint}
          keyboardType={type === "PHONE" ? "phone-pad" : "email-address"}
          autoCapitalize="none"
          autoCorrect={false}
          value={value}
          onChangeText={setValue}
        />
      </View>

      {!showPrivacy && (
        <ActionBar
          onBack={() => nav.goBack()}
          forwardEnabled={valid}
          onForward={() => {
            setSignupCredential(type, value);
            nav.navigate("Name");
          }}
        />
      )}

      {showPrivacy && (
        <View style={styles.privacyOverlay}>
          <View style={styles.privacyCard}>
            <Text style={styles.privacyTitle}>{S.privacyPolicy}</Text>
            <ScrollView style={styles.privacyBody}>
              <Text style={styles.privacyText}>
                Greenstand respects your privacy. The information you provide is
                used only to associate the trees you capture with your account
                and is handled according to the Greenstand privacy policy. Tap
                the green button below to accept and continue.
              </Text>
            </ScrollView>
            <View style={styles.privacyAccept}>
              <ApprovalButton
                approval
                size={50}
                accessibilityLabel={S.acceptPrivacyPolicy}
                onPress={() => setShowPrivacy(false)}
              />
            </View>
          </View>
        </View>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  body: {
    flex: 1,
    paddingHorizontal: 16,
    justifyContent: "center",
  },
  toggleRow: {
    flexDirection: "row",
    justifyContent: "center",
    paddingTop: 10,
    marginBottom: 16,
  },
  toggleText: {
    color: TextColors.darkText,
    fontSize: 14,
    fontWeight: "bold",
    fontFamily: Fonts.bold,
  },
  input: { marginHorizontal: 16, marginVertical: 8 },
  privacyOverlay: {
    position: "absolute",
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    backgroundColor: AppColors.Gray,
    paddingHorizontal: 30,
    paddingTop: 10,
    paddingBottom: 40,
  },
  privacyCard: {
    flex: 1,
    borderWidth: 1,
    borderColor: AppColors.Green,
    borderRadius: 12,
    backgroundColor: AppColors.Gray,
    padding: 16,
  },
  privacyTitle: {
    color: TextColors.primaryText,
    fontSize: 24,
    fontWeight: "bold",
    fontFamily: Fonts.bold,
    marginBottom: 12,
  },
  privacyBody: { flex: 1 },
  privacyText: {
    color: TextColors.lightText,
    fontSize: 14,
    lineHeight: 22,
    fontFamily: Fonts.regular,
  },
  privacyAccept: { alignItems: "center", paddingTop: 16 },
});
