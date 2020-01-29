@isTest
public with sharing class Vend_Sync_SharedCodeTest {

	@isTest
	private static void codeCoverage() {

		Vend_Sync_SharedCode.CodeCoverageHack();

		User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
		System.runAs(thisUser) {

			EmailTemplate template = new EmailTemplate(
				Name = 'Email_Template',
				DeveloperName = 'Email_Template',
				Body = 'Body',
				HtmlValue = '</br>',
				Subject = 'Subject',
				IsActive = true,
				FolderId = UserInfo.getUserId(),
				TemplateType = 'text'
			);
			insert template;

			Account account = new Account(
				Name = 'Name'
			);
			insert account;

			Contact contact = new Contact(
				LastName = 'LastName',
				Email = 'test@test.com'
			);
			insert contact;

			Messaging.SingleEmailMessage contactEmail = Vend_Sync_SharedCode.BuildContactEmail(template.Id, contact.Id, account.Id, contact.Email, new List<OrgWideEmailAddress>());
			Messaging.SingleEmailMessage contactEmail2 = Vend_Sync_SharedCode.BuildContactEmail_v2(template.Id, contact.Id, account.Id, contact.Email, new List<OrgWideEmailAddress>(), false);
			Messaging.SingleEmailMessage adminEmail = Vend_Sync_SharedCode.BuildAdminEmail(contact.Id, contact.Email, contact.Email, template.Name, 'Message Data', 'Error Message', true);

			Vend_Sync_SharedCode.SendEmails(
				new List<Messaging.SingleEmailMessage> {adminEmail, contactEmail, contactEmail2},
				contact.Email,
				template.DeveloperName,
				'Message Data',
				true);
		}

		Vend_Sync_SharedCode.UpdateAPIUsage(1, 1);
		Vend_Sync_SharedCode.NearSalesforceLimits(true);
	}
}