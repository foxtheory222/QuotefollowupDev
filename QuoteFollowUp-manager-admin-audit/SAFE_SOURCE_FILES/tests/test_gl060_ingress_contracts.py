import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
GL060_GENERATOR = REPO_ROOT / "scripts" / "create-southern-alberta-gl060-flow-solution.ps1"
MAILBOX_REPAIR = REPO_ROOT / "scripts" / "repair-southern-alberta-mailbox-trigger-definitions.ps1"
LIVE_XRM_REPAIR = REPO_ROOT / "scripts" / "repair-live-gl060-mailbox-ingress-xrm.ps1"
GL060_PROOF = REPO_ROOT / "scripts" / "prove-gl060-mailbox-ingress.ps1"
GL060_REPLAY = REPO_ROOT / "scripts" / "send-gl060-validation-replay.ps1"
SHARED_MAILBOX_FIND = REPO_ROOT / "scripts" / "find-shared-mailbox-messages.ps1"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


class Gl060IngressContractTests(unittest.TestCase):
    def test_gl060_generator_requires_attachment_bearing_gl060_mail(self) -> None:
        script = read_text(GL060_GENERATOR)
        self.assertIn('hasAttachments = $true', script)
        self.assertIn('subjectFilter = "GL060 P&L report"', script)
        self.assertIn('operationId = "SharedMailboxOnNewEmailV2"', script)

    def test_gl060_generator_preserves_mailbox_received_time_and_message_audit(self) -> None:
        script = read_text(GL060_GENERATOR)
        self.assertIn(
            "\"item/qfu_receivedon\" = \"@coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())\"",
            script,
        )
        self.assertIn(
            "\"item/qfu_startedon\" = \"@coalesce(triggerOutputs()?['body/receivedDateTime'], utcNow())\"",
            script,
        )
        self.assertIn("InternetMessageId=", script)
        self.assertIn("ReceivedDateTime=", script)

    def test_mailbox_repair_script_hardens_live_gl060_trigger_definitions(self) -> None:
        script = read_text(MAILBOX_REPAIR)
        self.assertIn('if ($DisplayName -like "*GL060-Inbox-Ingress*") {', script)
        self.assertIn('return "GL060 P&L report"', script)
        self.assertIn("$expectedHasAttachments = Get-ExpectedHasAttachments", script)
        self.assertIn("$expectedIncludeAttachments = Get-ExpectedIncludeAttachments", script)
        self.assertIn('has_attachments_updated = $false', script)
        self.assertIn('include_attachments_updated = $false', script)
        self.assertIn('NotePropertyName "hasAttachments"', script)
        self.assertIn('NotePropertyName "includeAttachments"', script)
        self.assertIn(
            'has_attachments_after = if ($afterTrigger.inputs.parameters.PSObject.Properties["hasAttachments"])',
            script,
        )
        self.assertIn(
            'include_attachments_after = if ($afterTrigger.inputs.parameters.PSObject.Properties["includeAttachments"])',
            script,
        )
        self.assertIn('Set-ObjectProperty -Object $rawParameters -Name "item/qfu_receivedon"', script)
        self.assertIn('Set-ObjectProperty -Object $rawParameters -Name "item/qfu_processingnotes"', script)
        self.assertIn('Set-ObjectProperty -Object $batchParameters -Name "item/qfu_startedon"', script)
        self.assertIn('Set-ObjectProperty -Object $batchParameters -Name "item/qfu_notes"', script)

    def test_live_xrm_repair_script_patches_gl060_trigger_and_audit_contract(self) -> None:
        script = read_text(LIVE_XRM_REPAIR)
        self.assertIn('DisplayName = "4171-GL060-Inbox-Ingress"', script)
        self.assertIn('WorkflowId = "<GUID>"', script)
        self.assertIn('operationId -ne "SharedMailboxOnNewEmailV2"', script)
        self.assertIn('Set-ObjectProperty -Object $parameters -Name "hasAttachments" -Value $true', script)
        self.assertIn('Set-ObjectProperty -Object $parameters -Name "includeAttachments" -Value $true', script)
        self.assertIn('Set-ObjectProperty -Object $rawParameters -Name "item/qfu_receivedon" -Value $expectedReceivedOn', script)
        self.assertIn('Set-ObjectProperty -Object $rawParameters -Name "item/qfu_rawcontentbase64" -Value $expectedRawContent', script)
        self.assertIn('Set-ObjectProperty -Object $batchParameters -Name "item/qfu_startedon" -Value $expectedReceivedOn', script)
        self.assertIn('Set-CrmRecord -conn $connection -EntityLogicalName workflow', script)
        self.assertIn('Set-CrmRecordState -conn $connection -EntityLogicalName workflow', script)

    def test_gl060_proof_script_queries_rawdocuments_and_ingestion_batches_since_marker(self) -> None:
        script = read_text(GL060_PROOF)
        self.assertIn('[datetime]$SinceUtc = [datetime]::MinValue', script)
        self.assertIn('EntityLogicalName "qfu_rawdocument"', script)
        self.assertIn('EntityLogicalName "qfu_ingestionbatch"', script)
        self.assertIn('qfu_processingnotes', script)
        self.assertIn('qfu_triggerflow', script)
        self.assertIn('[switch]$ValidationReplayOnly', script)
        self.assertIn('ValidationReplayFilter', script)
        self.assertIn('validation_replay_only', script)
        self.assertIn('rawdocument_count_since', script)
        self.assertIn('ingestionbatch_count_since', script)

    def test_gl060_replay_script_sends_extracted_validation_pdfs_to_branch_mailboxes(self) -> None:
        script = read_text(GL060_REPLAY)
        self.assertIn('AttachmentRoot = "C:\\Users\\smcfarlane\\Desktop\\WorkBench\\QuoteFollowUpRegion\\results\\gl060-example-extracted-20260420"', script)
        self.assertIn('Subject = "GL060 P&L report - Last month"', script)
        self.assertIn('New-Object -ComObject Outlook.Application', script)
        self.assertIn('"{0}-GL060 Report - Profit Center - CanSC - Publish.pdf" -f $branchCode', script)
        self.assertIn('$mail.Send()', script)
        self.assertIn('$resolvedRecipient = $namespace.CreateRecipient($recipientAddress)', script)
        self.assertIn('recipient_resolved', script)
        self.assertIn('replay_stamp', script)

    def test_shared_mailbox_find_script_restricts_by_received_time_and_subject(self) -> None:
        script = read_text(SHARED_MAILBOX_FIND)
        self.assertIn('$candidateItems = $items.Restrict("[ReceivedTime] >= \'" + $receivedAfterLocal + "\'")', script)
        self.assertIn('$subject -notlike ("*" + $SubjectContains + "*")', script)
        self.assertIn('New-Object -ComObject Outlook.Application', script)
        self.assertIn('attachment_count', script)


if __name__ == "__main__":
    unittest.main()
