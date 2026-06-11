import React, { useState } from "react";
import { StyleSheet, Text, TextInput, View } from "react-native";
import { useNavigation } from "@react-navigation/native";
import { ActionBar } from "../components/ActionBar";
import { S } from "../strings";
import { Nav } from "../navigation";
import { setSignupName } from "../signupDraft";

// Name entry. EditText[0] = first name, EditText[1] = last name.
export default function NameScreen() {
  const nav = useNavigation<Nav<"Name">>();
  const [first, setFirst] = useState("");
  const [last, setLast] = useState("");

  return (
    <View style={styles.root}>
      <View style={styles.body}>
        <Text style={styles.label}>{S.firstName}</Text>
        <TextInput
          style={styles.input}
          placeholder={S.firstName}
          value={first}
          onChangeText={setFirst}
        />
        <Text style={styles.label}>{S.lastName}</Text>
        <TextInput
          style={styles.input}
          placeholder={S.lastName}
          value={last}
          onChangeText={setLast}
        />
      </View>
      <ActionBar
        onBack={() => nav.goBack()}
        forwardEnabled={first.trim().length > 0 && last.trim().length > 0}
        onForward={() => {
          setSignupName(first.trim(), last.trim());
          nav.navigate("Selfie");
        }}
      />
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
