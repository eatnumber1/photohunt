<?xml version="1.0"?>

<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
	<xsl:template match="/photohunt">
		<games>
			<xsl:for-each select="games/game">
				<game>
					<id><xsl:value-of select="id"/></id>
					<start><xsl:value-of select="start"/></start>
					<end><xsl:value-of select="end"/></end>
					<max_photos><xsl:value-of select="max_photos"/></max_photos>
					<max_judged_photos><xsl:value-of select="max_judged_photos"/></max_judged_photos>
				</game>
			</xsl:for-each>
		</games>
	</xsl:template>
</xsl:stylesheet>
