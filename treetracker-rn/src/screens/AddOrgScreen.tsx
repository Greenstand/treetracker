import React, { useState } from "react";
import { StyleSheet, Text, TextInput, View } from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
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
    <View style={styles.root}>
      <View style={styles.body}>
        <Text style={styles.label}>{S.organization}</Text>
        <TextInput
          style={styles.input}
          placeholder={S.organizationHint}
          value={org}
          onChangeText={setOrg}
        />
      </View>
      <ActionBar onBack={() => nav.goBack()} onForward={next} />
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#fff" },
  body: { flex: 1, padding: 24, paddingTop: 60, gap: 12 },
  label: { fontSize: 18, fontWeight: "600", color: "#1B5E20" },
  input: {
    borderWidth: 1,
    borderColor: "#999",
    borderRadius: 8,
    padding: 14,
    fontSize: 16,
  },
});
