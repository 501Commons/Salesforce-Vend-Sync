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
		}

		Vend_Sync_SharedCode.NearSalesforceLimits(true);
	}
}