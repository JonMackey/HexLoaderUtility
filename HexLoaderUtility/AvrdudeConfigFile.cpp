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
//  AvrdudeElement.cpp
//
//  Copyright © 2020 Jon Mackey. All rights reserved.
//
#include "AvrdudeConfigFile.h"
#include "FileInputBuffer.h"
#include "JSONElement.h"

struct SKey
{
	const char*	name;
	uint32_t	expectedType;
};

const SKey kPartKeys[] =
{
	{"id", IJSONElement::eString | 0x10},	// Flag part key id string
	{"desc", IJSONElement::eString | 0x20},	// Flag part description string
	{"signature", IJSONElement::eNumber},
	{"chip_erase_delay", IJSONElement::eNumber},
	{"resetdelay", IJSONElement::eNumber},
	{"stk500_devcode", IJSONElement::eNumber},
	{"memory", IJSONElement::eObject}
};

const SKey kMemoryKeys[] =
{
	{"min_write_delay", IJSONElement::eNumber},
	{"delay", IJSONElement::eNumber},
	{"blocksize", IJSONElement::eNumber},
	{"size", IJSONElement::eNumber},
	{"page_size", IJSONElement::eNumber},
	{"readsize", IJSONElement::eNumber}
};

/***************************** AvrdudeConfigFile ******************************/
AvrdudeConfigFile::AvrdudeConfigFile(void)
	: mError(eNoErr)
{
	for (uint32_t i = 0; i < sizeof(kPartKeys)/sizeof(SKey); i++)
	{
		mPartKeyMap.insert(AvrdudeKeyMap::value_type(kPartKeys[i].name, kPartKeys[i].expectedType));
	}
	for (uint32_t i = 0; i < sizeof(kMemoryKeys)/sizeof(SKey); i++)
	{
		mMemoryKeyMap.insert(AvrdudeKeyMap::value_type(kMemoryKeys[i].name, kMemoryKeys[i].expectedType));
	}
}

/***************************** ~AvrdudeConfigFile *****************************/
AvrdudeConfigFile::~AvrdudeConfigFile(void)
{
}

/********************************** ReadFile **********************************/
bool AvrdudeConfigFile::ReadFile(
	const char*	inPath)
{
	FileInputBuffer	inputBuffer(inPath);
	if (inputBuffer.IsValid())
	{
		ReadHLEntries(inputBuffer);
	}
	return(mError==eNoErr);
}

/************************************ Dump ************************************/
void AvrdudeConfigFile::Dump(void)
{
	std::string	dumpStr;
	Write(mRootObject, dumpStr);
	fprintf(stderr, "%s\n", dumpStr.c_str());
}

/*********************************** Export ***********************************/
/*
*	Iteratively applies all parents to the entry pointed to by inKey.
*	inKey is expected to be the part desc as written in the avrdude.conf file.
*	The passed key will be converted to lowercase before converting using it to
*	lookup the part id.
*/
JSONObject* AvrdudeConfigFile::Export(
	const std::string&	inPartDesc)
{
	JSONObject*	entry = nullptr;
	JSONObject*	element = nullptr;
	std::string	lcKeyStr(inPartDesc);
	StrStrMap::const_iterator	idItr = mDescToIDMap.find(ToLowercase(lcKeyStr));
	if (idItr != mDescToIDMap.end())
	{
		std::string	entryKey(idItr->second);
		entryKey+='.';
		element = (JSONObject*)(mRootObject->GetElement(entryKey, IJSONElement::eObject));
		if (element)
		{
			entry = (JSONObject*)(element->Copy());
			if (entry)
			{
				JSONString*	parent = (JSONString*)(entry->GetElement("parent", IJSONElement::eString));
				for (; parent; parent = (JSONString*)(element->GetElement("parent", IJSONElement::eString)))
				{
					std::string	parentIDStr(parent->GetString());
					parentIDStr+='.';
					element = (JSONObject*)(mRootObject->GetElement(parentIDStr, IJSONElement::eObject));
					if (element)
					{
						Apply((JSONObject*)element, entry);
						continue;
					}
					break;
				}
			}
		}
	}
	return(entry);
}

/******************************** ToLowercase *********************************/
std::string& AvrdudeConfigFile::ToLowercase(
	std::string&	ioString)
{
	std::transform(ioString.begin(), ioString.end(), ioString.begin(),
							[](unsigned char c){ return std::tolower(c); });
	return(ioString);
}

/************************* SkipWhitespaceAndComments **************************/
/*
*	For some reason the conf file allows for both hash and block comments.
*	This routine skips both types till a non-space is hit.
*/
uint8_t AvrdudeConfigFile::SkipWhitespaceAndComments(
	InputBuffer&	inInputBuffer)
{
	uint8_t	thisChar;
	while (true)
	{
		thisChar = inInputBuffer.SkipWhitespaceAndHashComments();
		if (thisChar != '/')
		{
			break;
		}
		thisChar = inInputBuffer.SkipWhitespaceAndComments();
	}
	return(thisChar);
}

/******************************* ReadNextToken ********************************/
/*
*	Returns the next token and the character following the token.
*
*	Ex: "part parent" would return "part" and 'p'
*		"parent \"name\"" would return "parent" and '\"'
*		"part # some comment\n\tid =" would return "part" and the 'i' of "id"
*		"id = "some ID" would return "id" and '='
*		"# some comment\n\t; would return "" and ';'
*/
uint8_t AvrdudeConfigFile::ReadNextToken(
	InputBuffer&	inInputBuffer,
	std::string&	outToken)
{
	outToken.clear();
	uint8_t	thisChar = SkipWhitespaceAndComments(inInputBuffer);
	if (thisChar)
	{
		inInputBuffer.StartSubString();
		do
		{
			switch (thisChar)
			{
				/*
				*	Any reserved character terminates the token.
				*	Return the reserved character.
				*/
				case '=':
				case '\"':
				case ';':
					inInputBuffer.AppendSubString(outToken);
					break;
				/*
				*	Any whitespace terminates the token.
				*	return the next non-whitespace character after the token.
				*/
				case ' ':
				case '\t':
				case '\n':
				case '\r':
					inInputBuffer.AppendSubString(outToken);
					thisChar = SkipWhitespaceAndComments(inInputBuffer);
					break;
				default:
					thisChar = inInputBuffer.NextChar();
					continue;
			}
			break;
		} while (thisChar);
	}
	return(thisChar);
}

/*************************** ReadUInt32NumberValue ****************************/
/*
*	Returns a string representation of the number.
*/
uint8_t AvrdudeConfigFile::ReadUInt32NumberValue(
	InputBuffer&	inInputBuffer,
	std::string&	outValue)
{
	bool	bitwiseNot = false;
	bool 	isHex = false;
	uint32_t	value = 0;
	uint8_t	thisChar = SkipWhitespaceAndComments(inInputBuffer);
	if (thisChar)
	{
		
		bitwiseNot = thisChar == '~';
		/*
		*	If notted THEN
		*	get the next char after the not.
		*/
		if (bitwiseNot)
		{
			inInputBuffer++;
			thisChar = SkipWhitespaceAndComments(inInputBuffer);
		}
		if (thisChar == '0')
		{
			inInputBuffer.PushMark();
			isHex = inInputBuffer.NextChar() == 'x';
			inInputBuffer.PopMark(!isHex);
			thisChar = inInputBuffer.NextChar();
		}
		// Now just consume characters till a non valid numeric char is hit.
		if (isHex)
		{
			uint8_t	byteCount = 0;
			do 
			{
				for (; isxdigit(thisChar); thisChar = inInputBuffer.NextChar())
				{
					thisChar -= '0';
					if (thisChar > 9)
					{
						thisChar -= 7;
						if (thisChar > 15)
						{
							thisChar -= 32;
						}
					}
					value = (value << 4) + thisChar;
				}
				thisChar = inInputBuffer.SkipWhitespace();
				/*
				*	Special case for signatures.
				*	Append the next byte if it has a hex prefix.
				*	e.g. 0x33 0x44 0x55; will parse as 0x334455
				*/
				if (thisChar == '0' &&
					inInputBuffer.NextChar() == 'x')
				{
					byteCount++;
					thisChar = inInputBuffer.NextChar();
					continue;
				}
				break;
			} while (byteCount < 3);
		} else
		{
			for (; isdigit(thisChar); thisChar = inInputBuffer.NextChar())
			{
				value = (value * 10) + (thisChar - '0');
			}
			thisChar = inInputBuffer.SkipWhitespace();
		}
	}
	/*
	*	If this is the expected value terminator...
	*/
	if (thisChar == ';')
	{
		char numBuff[50];
		if (bitwiseNot)
		{
			outValue.assign("~");
		}
		snprintf(numBuff, 50, isHex ? "0x%x" : "%d", value);
		outValue.append(numBuff);
	} else
	{
		mError = eUnterminatedValueErr;
	}
	return(thisChar);
}

/********************************* SkipEntry **********************************/
uint8_t AvrdudeConfigFile::SkipEntry(
	InputBuffer&	inInputBuffer)
{
	uint8_t	thisChar;
	std::string	token;
	
	thisChar = ReadNextToken(inInputBuffer, token);
	/*
	*	If the entry has a parent THEN
	*	skip the parent name.
	*/
	if (token.compare("parent") == 0)
	{
		if (thisChar == '\"')
		{
			bool skipNext = false;
			thisChar = inInputBuffer.NextChar();	// Step past the leading quote
			for (; thisChar; thisChar = inInputBuffer.NextChar())
			{
				if (skipNext == false)
				{
					switch(thisChar)
					{
						case '\"':	// end of quoted value hit
							break;
						case '\n':	// If we hit the end of the line before hitting the quote, then fail
							mError = eQuoteNotClosedErr;
							break;
						case '\\':
							skipNext = true;
						default:
							continue;
					}
					break;
				} else
				{
					skipNext = false;
				}
			}
		} else
		{
			// fail, the expected parent name wasn't found.
			mError = eMissingParentNameErr;
		}
		
		if (thisChar && !mError)
		{
			inInputBuffer++; // Skip the closing quote
			thisChar = ReadNextToken(inInputBuffer, token);
		}
	}
	for (; thisChar && !mError; thisChar = ReadNextToken(inInputBuffer, token))
	{
		switch (thisChar)
		{
			case '=':
				if (SkipValue(inInputBuffer))
				{
					continue;
				}
				break;
			case ';':
				break;
		}
		break;
	}
	return(thisChar ? inInputBuffer.NextChar() : 0);
}

/********************************* SkipValue **********************************/
/*
*	This is called with the CurrChar pointing to the assignment operator.
*	This will scan till a semicolon is hit.  Any intervening quotes and comments
*	are also skipped (semicolons within quotes or comments are ignored.)
*
*	On return, CurrChar points to the character after the terminating semicolon.
*/
uint8_t AvrdudeConfigFile::SkipValue(
	InputBuffer&	inInputBuffer)
{
	uint8_t	thisChar = inInputBuffer.NextChar();	// Step past the assignment operator
	for (; thisChar; thisChar = inInputBuffer.NextChar())
	{
		thisChar = SkipWhitespaceAndComments(inInputBuffer);
		switch(thisChar)
		{
			case '\"':
			{
				bool skipNext = false;
				thisChar = inInputBuffer.NextChar();	// Step past the leading quote
				for (; thisChar; thisChar = inInputBuffer.NextChar())
				{
					if (skipNext == false)
					{
						switch(thisChar)
						{
							case '\"':	// end of quoted value hit
								break;
							case '\n':	// If we hit the end of the line before hitting the quote, then fail
								mError = eQuoteNotClosedErr;
								break;
							case '\\':
								skipNext = true;
							default:
								continue;
						}
						break;
					} else
					{
						skipNext = false;
					}
				}
				if (thisChar && !mError)
				{
					continue;
				}
				break;
			}
			case ';':
				thisChar = inInputBuffer.NextChar();	// Step past the value terminator
				break;
			default:
				continue;
		}
		break;
	}
	return(thisChar);
}

/******************************* ReadHLEntries ********************************/
/*
*	Read the next high level entry.  Only part entries in this context are read.
*	Programmer entries and default key/values are skipped.
*/
uint8_t AvrdudeConfigFile::ReadHLEntries(
	InputBuffer&	inInputBuffer)
{
	std::string	token;
	uint8_t	thisChar = ReadNextToken(inInputBuffer, token);
	for(; thisChar && !mError; thisChar = ReadNextToken(inInputBuffer, token))
	{
		switch(thisChar)
		{
			/*
			*	An assignment operator at this level means that the token isn't
			*	an entry type name.  Skip its value and continue scanning for a
			*	part.
			*/
			case '=':
				if (SkipValue(inInputBuffer))
				{
					continue;
				}
				mError = eValueErr;
				break;
			/*
			*	Entries, both part and programmer, don't have names.
			*	Flag this as a fatal error.
			*/
			case '\"':	// entry name (in this context)
				mError = eReservedCharErr;
				break;
			/*
			*	Error, empty entry.
			*	Entries must contain a key/value containing the id.
			*/
			case ';':	// end of entry (in this context)
				mError = eEmptyEntryErr;
				break;
			default:
				/*
				*	Any non-reserved character means that this is an entry.
				*	In this context there are only two entry types allowed, part and
				*	programmer.
				*/
				uint8_t	entryType = GetHLEntryType(token);
				switch (entryType)
				{
					case ePart:
						if (ReadPartEntry(inInputBuffer))
						{
							continue;
						}
						break;
					case eProgrammer:
						if (SkipEntry(inInputBuffer))
						{
							continue;
						}
						break;
					default:
						mError = eInvalidEntryTypeErr;
						break;
				}
				break;
		}
		break;
	}
	return(thisChar);
}

/******************************* ReadPartEntry ********************************/
/*
*	Reads the part entry's key/values.  Only select key/values are retained, all
*	others are skipped.
*/
uint8_t AvrdudeConfigFile::ReadPartEntry(
	InputBuffer&	inInputBuffer)
{
	std::string	token;
	std::string	name;
	JSONObject*	thisEntry = new JSONObject;
	std::string	entryKey;
	std::string	entryDesc;
	uint8_t	thisChar = ReadNextToken(inInputBuffer, token);
	/*
	*	If the part has a parent THEN
	*	get the required parent name and add it to the entry as a key/value.
	*/
	if (token.compare("parent") == 0)
	{
		if (thisChar == '\"')
		{
			inInputBuffer++; // Skip the leading quote.
			inInputBuffer.ReadTillNextQuote(false, name);
			InsertKeyValue(thisEntry, token, name);
		} else
		{
			// fail, the expected parent name wasn't found.
			mError = eMissingParentNameErr;
		}
		thisChar = ReadNextToken(inInputBuffer, token);
	}
	for (; thisChar && !mError; thisChar = ReadNextToken(inInputBuffer, token))
	{
		AvrdudeKeyMap::const_iterator	itr = mPartKeyMap.find(token);
		if (itr != mPartKeyMap.end())
		{
			switch (itr->second)
			{
				case IJSONElement::eObject:	// memory entry
					if (thisChar == '\"')
					{
						inInputBuffer++; // Skip the leading quote.
						name.clear();
						inInputBuffer.ReadTillNextQuote(false, name);
						if (name.compare("flash") == 0 ||
							name.compare("eeprom") == 0)
						{
							JSONObject*	memoryEntry = ReadMemoryEntry(inInputBuffer);
							if (memoryEntry)
							{
								ApplyWithPrefix(memoryEntry, thisEntry, name);
								delete memoryEntry;
							}
						} else
						{
							SkipEntry(inInputBuffer);
						}
						continue;
					} else
					{
						mError = eMissingMemoryTypeErr;
					}
					break;
				case IJSONElement::eString:
				case IJSONElement::eString | 0x10:
				case IJSONElement::eString | 0x20:
					inInputBuffer++;	// skip the assignment operator
					thisChar = SkipWhitespaceAndComments(inInputBuffer);
					if (thisChar == '\"')
					{
						std::string	valueStr;
						inInputBuffer++;	// skip the leading quote
						thisChar = inInputBuffer.ReadTillNextQuote(false, valueStr);
						if (thisChar)
						{
							thisChar = SkipWhitespaceAndComments(inInputBuffer);
							if (thisChar == ';')
							{
								if (itr->second & 0x10)
								{
									if (valueStr.length() > 0)
									{
										entryKey.assign(valueStr);
									} else
									{
										mError = eEmptyIDStrErr;
									}
								} else if (itr->second & 0x20)
								{
									if (valueStr.length() > 0)
									{
										entryDesc.assign(valueStr);
									} else
									{
										mError = eEmptyDescStrErr;
									}
								}
								if (!mError)
								{
									InsertKeyValue(thisEntry, token, valueStr);
									inInputBuffer++;	// skip the value terminator
									continue;
								}
							}
						}
					} else
					{
						mError = eUnexpectedCharErr;
					}
					break;
				case IJSONElement::eNumber:
				{
					std::string	value32;
					inInputBuffer++;	// skip the assignment operator
					thisChar = ReadUInt32NumberValue(inInputBuffer, value32);
					if (thisChar == ';')
					{
						InsertKeyValue(thisEntry, token, value32);
						inInputBuffer++;	// skip the value terminator
						continue;
					}
					break;
				}
			}
		} else if (thisChar == '=')
		{
			SkipValue(inInputBuffer);
			continue;
		} else if (thisChar == ';')
		{
			inInputBuffer++;	// skip the value terminator
		} else
		{
			mError = eUnexpectedCharErr;
		}
		break;
	}
	if (entryKey.length() && entryDesc.length() && !mError)
	{
		mDescToIDMap.insert(StrStrMap::value_type(ToLowercase(entryDesc), entryKey));
		entryKey+='.';
		mRootObject->InsertElement(entryKey, thisEntry);
	} else
	{
		delete thisEntry;
		mError = eMissingEntryKeyErr;
	}
	return(mError ? 0 : inInputBuffer.CurrChar());
}

/****************************** ReadMemoryEntry *******************************/
/*
*	Reads the memory entry's key/values.  Only select key/values are retained,
*	all others are skipped.
*/
JSONObject* AvrdudeConfigFile::ReadMemoryEntry(
	InputBuffer&	inInputBuffer)
{
	std::string	token;
	JSONObject*	thisEntry = new JSONObject;
	std::string	entryKey;
	uint8_t	thisChar = ReadNextToken(inInputBuffer, token);
	for (; thisChar && !mError; thisChar = ReadNextToken(inInputBuffer, token))
	{
		if (thisChar == '=')
		{
			AvrdudeKeyMap::const_iterator	itr = mMemoryKeyMap.find(token);
			if (itr != mMemoryKeyMap.end())
			{
				std::string	value32;
				inInputBuffer++;	// skip the assignment operator
				thisChar = ReadUInt32NumberValue(inInputBuffer, value32);
				if (thisChar == ';')
				{
					InsertKeyValue(thisEntry, token, value32);
					inInputBuffer++;	// skip the value terminator
					continue;
				} else
				{
					mError = eUnexpectedCharErr;
				}
			} else
			{
				SkipValue(inInputBuffer);
				continue;
			}
		} else if (thisChar == ';')
		{
			inInputBuffer++;	// skip the value terminator
		} else
		{
			mError = eUnexpectedCharErr;
		}
		break;
	}
	if (mError)
	{
		delete thisEntry;
		thisEntry = nullptr;
	}
	return(thisEntry);
}

/******************************* GetHLEntryType *******************************/
uint8_t AvrdudeConfigFile::GetHLEntryType(
	std::string&	inToken)
{
	uint8_t	entryType = eInvalidEntryType;
	if (inToken.compare("part") == 0)
	{
		entryType = ePart;
	} else if (inToken.compare("programmer") == 0)
	{
		entryType = eProgrammer;
	} 
	return(entryType);
}

/********************************** Apply *************************************/
/*
*	Applies inEntry to this entry by adding any key/values that don't exist.
*/
void AvrdudeConfigFile::Apply(
	const JSONObject*	inEntryToApply,
	JSONObject*			inEntryToApplyTo)
{
	JSONElementMap::const_iterator	itr = inEntryToApply->GetMap().begin();
	JSONElementMap::const_iterator	itrEnd = inEntryToApply->GetMap().end();
	JSONElementMap&	map = inEntryToApplyTo->GetMap();
	
	for (; itr != itrEnd; itr++)
	{
		JSONElementMap::const_iterator	fItr = map.find(itr->first);
		if (fItr == map.end())
		{
			map.insert(JSONElementMap::value_type(itr->first, itr->second->Copy()));
		}
	}
}
/********************************** ApplyWithPrefix *************************************/
/*
*	Applies inEntry to this entry by adding any key/values that don't exist.
*	All keys will have the prefix added to the keys before searching for a
*	match.  This essentiall should flatten the entry.
*/
void AvrdudeConfigFile::ApplyWithPrefix(
	const JSONObject*	inEntryToApply,
	JSONObject*			inEntryToApplyTo,
	std::string&		inPrefix)
{
	JSONElementMap::const_iterator	itr = inEntryToApply->GetMap().begin();
	JSONElementMap::const_iterator	itrEnd = inEntryToApply->GetMap().end();
	JSONElementMap&	map = inEntryToApplyTo->GetMap();
	
	std::string	prefix(inPrefix);
	prefix += '.';
	
	std::string	keyWithPrefix;
	for (; itr != itrEnd; itr++)
	{
		keyWithPrefix.assign(prefix);
		keyWithPrefix.append(itr->first);
		JSONElementMap::const_iterator	fItr = map.find(keyWithPrefix);
		if (fItr == map.end())
		{
			map.insert(JSONElementMap::value_type(keyWithPrefix, itr->second->Copy()));
		}
	}
}

/********************************** Write *************************************/
/*
*	A recursive routine that writes a flattened version of the passed entry.
*	It's assumed that inEntry is either the object that holds all of the parsed
*	part entries or an individual part entry (with no child entries.)
*/
void AvrdudeConfigFile::Write(
	const JSONObject*	inEntry,
	std::string&		outString)
{
	const JSONElementMap&	map = inEntry->GetMap();
	JSONElementMap::const_iterator	itr = map.begin();
	JSONElementMap::const_iterator	itrEnd = map.end();
	if (itr != itrEnd)
	{
		while (true)
		{
			switch (itr->second->GetType())
			{
				case IJSONElement::eString:
					outString.append(itr->first);
					outString.append("=");
					outString.append(((const JSONString*)itr->second)->GetString());
					break;
				case IJSONElement::eObject:
					outString.append((std::string::size_type)itr->first.size() + 10, '#');
					outString += '\n';
					outString.append("#### ");
					outString.append(itr->first);
					outString.append(" ####\n");
					outString.append((std::string::size_type)itr->first.size() + 10, '#');
					outString += '\n';
					Write((const JSONObject*)itr->second, outString);
					break;
				default:
					break;
			}
			outString += '\n';
			++itr;
			if (itr != itrEnd)
			{
				continue;
			}
			break;
		}
	}
}

/******************************* InsertKeyValue *******************************/
/*
*	Inserts a string element without parsing the key.
*/
void AvrdudeConfigFile::InsertKeyValue(
	JSONObject*			inEntry,
	const std::string&	inKey,
	const std::string&	inValue)
{
	JSONString*	stringElem = new JSONString(inValue);
	inEntry->InsertElement(inKey, stringElem);
}

/********************************* IDForDesc **********************************/
bool AvrdudeConfigFile::IDForDesc(
	const std::string&	inDesc,
	bool				inAppendDelimiter,
	std::string&		outID) const
{
	std::string lcDesc(inDesc);
	StrStrMap::const_iterator	idItr = mDescToIDMap.find(ToLowercase(lcDesc));
	bool	foundID = idItr != mDescToIDMap.end();
	if (foundID)
	{
		outID.assign(idItr->second);
		if (inAppendDelimiter)
		{
			outID+='.';
		}
	}
	return(foundID);
}

#pragma mark - AvrdudeConfigFiles
/***************************** AvrdudeConfigFiles *****************************/
AvrdudeConfigFiles::AvrdudeConfigFiles(void)
{
}

/**************************** ~AvrdudeConfigFiles *****************************/
AvrdudeConfigFiles::~AvrdudeConfigFiles(void)
{
	AvrdudeConfigFileMap::iterator	itr = mMap.begin();
	AvrdudeConfigFileMap::iterator	itrEnd = mMap.end();

	for (; itr != itrEnd; ++itr)
	{
		delete (*itr).second;
	}
}

/****************************** GetConfigForPath ******************************/
AvrdudeConfigFile* AvrdudeConfigFiles::GetConfigForPath(
	const std::string&		inPath) const
{
	AvrdudeConfigFileMap::const_iterator itr = mMap.find(inPath);
	return(itr != mMap.end() ? itr->second : NULL);
}

/*************************** EraseAvrdudeConfigFile ***************************/
void AvrdudeConfigFiles::EraseAvrdudeConfigFile(
	const std::string&		inPath)
{
	AvrdudeConfigFileMap::iterator	itr = mMap.find(inPath);
	if (itr != mMap.end())
	{
		delete itr->second;
		mMap.erase(itr);
	}
}

/*************************** AdoptAvrdudeConfigFile ***************************/
void AvrdudeConfigFiles::AdoptAvrdudeConfigFile(
	const std::string&		inPath,
	AvrdudeConfigFile*		inConfigFile)
{
	EraseAvrdudeConfigFile(inPath);
	mMap.insert(AvrdudeConfigFileMap::value_type(inPath, inConfigFile));
}
