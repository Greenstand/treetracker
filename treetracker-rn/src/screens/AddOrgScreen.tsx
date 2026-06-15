import React, { useState } from "react";
import { StyleSheet, Text, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { Screen, TopBar } from "../components/Layout";
import { BorderedTextField } from "../components/BorderedTextField";
import { Fonts, TextColors } from "../theme";
import { S } from "../strings";
import { Nav, Rt } from "../navigation";
import { addSession } from "../store";
import { uuidLike } from "../uuid";

export default function AddOrgScreen() {
  const nav = useNavigation<Nav<"AddOrg">>();
  const route = useRoute<Rt<"AddOrg">>();
  const [org, setOrg] = useState("");

  async function next() {
    const sessionId = uuidLike();
    await addSession({
      id: sessionId,
      organization: org.trim(),
      originUserId: route.params.userUuid,
      targetWallet: route.params.wallet,
    });
    nav.navigate("TreeCapture", { sessionId });
  }

  return (
    <Screen>
      <TopBar />
      <View style={styles.body}>
        <Text style={styles.label}>{S.organization}</Text>
        <BorderedTextField
          style={styles.input}
          placeholder={S.organization}
          autoCorrect={false}
          value={org}
          onChangeText={setOrg}
        />
      </View>
      <ActionBar onBack={() => nav.goBack()} onForward={next} />
    </Screen>
  );
}

const styles = StyleSheet.create({
  body: { flex: 1, paddingHorizontal: 24, paddingTop: 60 },
  label: {
    color: TextColors.primaryText,
    fontSize: 16,
    fontWeight: "bold",
    fontFamily: Fonts.bold,
    marginBottom: 8,
  },
  input: { alignSelf: "stretch" },
});
