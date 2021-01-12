/*******************************************************************************
	License
	****************************************************************************
	This program is free software; you can redistribute it
	and/or modify it under the terms of the GNU General
	Public License as published by the Free Software
	Foundation; either version 3 of the License, or
	(at your option) any later version.
 
	This program is distributed in the hope that it will
	be useful, but WITHOUT ANY WARRANTY; without even the
	implied warranty of MERCHANTABILITY or FITNESS FOR A
	PARTICULAR PURPOSE. See the GNU General Public
	License for more details.
 
	Licence can be viewed at
	http://www.gnu.org/licenses/gpl-3.0.txt

	Please maintain this license information along with authorship
	and copyright notices in any redistribution of this code
*******************************************************************************/
//
//  AvrdudeElement.h
//
//  Copyright © 2020 Jon Mackey. All rights reserved.
//
/*
*	This is a partial avrdude.conf file parser implementation that reads
*	a small set of part information from a known valid file.
*
*	See ConfigurationFile.cpp, kPartKeys and kMemoryKeys for the list of keys
*	read/retained.
*
*	Key/values and programmer entries and are skipped.
*/
#pragma once
#include "ConfigurationFile.h"

typedef std::map<std::string, uint32_t> AvrdudeKeyMap;
typedef std::map<std::string, std::string> StrStrMap;

class AvrdudeConfigFile : public ConfigurationFile
{
public:
							AvrdudeConfigFile(void);
							~AvrdudeConfigFile(void);
	virtual bool			ReadFile(
								const char*				inPath);
	bool					IDForDesc(
								const std::string&		inDesc,
								bool					inAppendDelimiter,
								std::string&			outID) const;
	JSONObject*				Export(
								const std::string&		inPartDesc);
	void					Dump(void);
	uint8_t					Error(void) const
								{return(mError);}
	static void				Apply(
								const JSONObject*		inEntryToApply,
								JSONObject*				inEntryToApplyTo);
	static void				ApplyWithPrefix(
								const JSONObject*		inEntryToApply,
								JSONObject*				inEntryToApplyTo,
								std::string&			inPrefix);
	static void				InsertKeyValue(
								JSONObject*				inEntry,
								const std::string&		inKey,
								const std::string&		inValue);
	static void				Write(
								const JSONObject*		inEntry,
								std::string&			outString);
	static std::string&		ToLowercase(
								std::string&			ioString);
	enum EErrors
	{
		eNoErr,
		eUnterminatedValueErr,
		eQuoteNotClosedErr,
		eValueErr,
		eReservedCharErr,
		eEmptyEntryErr,
		eInvalidEntryTypeErr,
		eMissingParentNameErr,
		eMissingMemoryTypeErr,
		eEmptyIDStrErr,
		eEmptyDescStrErr,
		eUnexpectedCharErr,
		eMissingEntryKeyErr
	};
protected:
	enum EEntryType
	{
		eInvalidEntryType,
		ePart,
		eProgrammer
	};
	
	AvrdudeKeyMap	mPartKeyMap;
	AvrdudeKeyMap	mMemoryKeyMap;
	StrStrMap		mDescToIDMap;
	uint8_t	mError;

	static uint8_t			SkipWhitespaceAndComments(
								InputBuffer&			inInputBuffer);
	static uint8_t			ReadNextToken(
								InputBuffer&			inInputBuffer,
								std::string&			outToken);
	uint8_t					ReadUInt32NumberValue(
								InputBuffer&			inInputBuffer,
								std::string&			outValue);
	uint8_t					SkipEntry(
								InputBuffer&			inInputBuffer);
	uint8_t					SkipValue(
								InputBuffer&			inInputBuffer);
	uint8_t					ReadHLEntries(
								InputBuffer&			inInputBuffer);
	uint8_t					ReadPartEntry(
								InputBuffer&			inInputBuffer);
	JSONObject*				ReadMemoryEntry(
								InputBuffer&			inInputBuffer);
	uint8_t					GetHLEntryType(
								std::string&			inToken);
};

typedef std::map<std::string, AvrdudeConfigFile*> AvrdudeConfigFileMap;
class AvrdudeConfigFiles
{
public:
							AvrdudeConfigFiles(void);
							~AvrdudeConfigFiles(void);

	AvrdudeConfigFile*		GetConfigForPath(
								const std::string&		inPath) const;
	void					EraseAvrdudeConfigFile(
								const std::string&		inPath);
	void					AdoptAvrdudeConfigFile(
								const std::string&		inPath,
								AvrdudeConfigFile*		inConfigFile); // Takes ownership of inConfigFile.
protected:
	AvrdudeConfigFileMap	mMap;
};

