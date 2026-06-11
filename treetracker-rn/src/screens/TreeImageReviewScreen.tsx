import React, { useState } from "react";
import {
  Image,
  Modal,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";
import { useNavigation, useRoute } from "@react-navigation/native";
import { S } from "../strings";
import { Nav, Rt } from "../navigation";
import { addCapture } from "../store";
import { uuidLike } from "../uuid";

// Tree image review: NOTE dialog + Approve/Reject. Approve saves the capture and
// returns to the capture screen (matching the Android flow).
export default function TreeImageReviewScreen() {
  const nav = useNavigation<Nav<"TreeImageReview">>();
  const route = useRoute<Rt<"TreeImageReview">>();
  const { sessionId, photoUri, lat, lon } = route.params;
  const [note, setNote] = useState("");
  const [draftNote, setDraftNote] = useState("");
  const [noteOpen, setNoteOpen] = useState(false);

  async function approve() {
    await addCapture({
      id: uuidLike(),
      sessionId,
      lat,
      lon,
      note,
      photoPath: photoUri,
      capturedAt: new Date().toISOString(),
      absStepCount: 0,
      deltaStepCount: 0,
      uploaded: false,
    });
    nav.goBack();
  }

  return (
    <View style={styles.root}>
      {photoUri ? (
        <Image source={{ uri: photoUri }} style={styles.img} />
      ) : (
        <View style={[styles.img, styles.placeholder]}>
          <Text style={{ color: "#fff" }}>Tree</Text>
        </View>
      )}

      <Pressable
        onPress={() => {
          setDraftNote(note);
          setNoteOpen(true);
        }}
        style={styles.noteBtn}>
        <Text style={styles.noteBtnText}>{S.note}</Text>
      </Pressable>

      <View style={styles.controls}>
        <Pressable
          accessibilityLabel={S.rejectTree}
          accessibilityRole="button"
          onPress={() => nav.goBack()}
          style={[styles.action, styles.reject]}>
          <Text style={styles.actionText}>{"✕"}</Text>
        </Pressable>
        <Pressable
          accessibilityLabel={S.approveTree}
          accessibilityRole="button"
          onPress={approve}
          style={[styles.action, styles.approve]}>
          <Text style={styles.actionText}>{"✓"}</Text>
        </Pressable>
      </View>

      <Modal visible={noteOpen} transparent animationType="fade">
        <View style={styles.modalWrap}>
          <View style={styles.dialog}>
            <Text style={styles.dialogTitle}>{S.addNoteToTree}</Text>
            <TextInput
              style={styles.input}
              placeholder="Your note"
              value={draftNote}
              onChangeText={setDraftNote}
              autoFocus
            />
            <View style={styles.dialogButtons}>
              <Pressable
                onPress={() => setNoteOpen(false)}
                style={styles.dialogBtn}>
                <Text style={styles.dialogBtnText}>Cancel</Text>
              </Pressable>
              <Pressable
                accessibilityLabel={S.saveNote}
                accessibilityRole="button"
                onPress={() => {
                  setNote(draftNote);
                  setNoteOpen(false);
                }}
                style={styles.dialogBtn}>
                <Text style={styles.dialogBtnText}>Save</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: "#000" },
  img: { flex: 1, resizeMode: "cover" },
  placeholder: { alignItems: "center", justifyContent: "center" },
  noteBtn: {
    position: "absolute",
    top: 40,
    alignSelf: "center",
    backgroundColor: "#2E7D32",
    paddingHorizontal: 28,
    paddingVertical: 12,
    borderRadius: 24,
  },
  noteBtnText: { color: "#fff", fontSize: 18, fontWeight: "700" },
  controls: {
    flexDirection: "row",
    justifyContent: "space-around",
    paddingVertical: 24,
    backgroundColor: "#000",
  },
  action: {
    width: 64,
    height: 64,
    borderRadius: 32,
    alignItems: "center",
    justifyContent: "center",
  },
  reject: { backgroundColor: "#B71C1C" },
  approve: { backgroundColor: "#2E7D32" },
  actionText: { color: "#fff", fontSize: 28, fontWeight: "bold" },
  modalWrap: {
    flex: 1,
    backgroundColor: "rgba(0,0,0,0.5)",
    alignItems: "center",
    justifyContent: "center",
    padding: 24,
  },
  dialog: {
    width: "100%",
    backgroundColor: "#fff",
    borderRadius: 12,
    padding: 20,
    gap: 16,
  },
  dialogTitle: { fontSize: 18, fontWeight: "700", color: "#1B5E20" },
  input: {
    borderWidth: 1,
    borderColor: "#999",
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
  },
  dialogButtons: { flexDirection: "row", justifyContent: "flex-end", gap: 20 },
  dialogBtn: { paddingHorizontal: 12, paddingVertical: 8 },
  dialogBtnText: { fontSize: 16, color: "#2E7D32", fontWeight: "700" },
});
